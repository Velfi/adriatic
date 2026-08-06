package main
import "core:math"

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_mouse_limb_hull :: proc(
    points: []third_person.Vec3,
    radii: []f32,
    colors: []canvas2d.Color,
    forward: third_person.Vec3,
    cap_root := true,
) {
    MAX_RINGS :: 16
    SEGMENTS :: 12
    if len(points) < 2 || len(points) > MAX_RINGS || len(radii) != len(points) || len(colors) != len(points) {
        return
    }

    rings: [MAX_RINGS][SEGMENTS]third_person.Vec3
    normals: [MAX_RINGS][SEGMENTS]third_person.Vec3
    reference := linalg.normalize0(forward)
    previous_axis_x, previous_axis_z: third_person.Vec3
    for ring_index in 0 ..< len(points) {
        previous := max(ring_index - 1, 0)
        next := min(ring_index + 1, len(points) - 1)
        tangent := third_person.Vec3 {
            points[next].x - points[previous].x,
            points[next].y - points[previous].y,
            points[next].z - points[previous].z,
        }
        axis_y := linalg.normalize0(tangent)
        frame_reference := reference
        if ring_index > 0 do frame_reference = previous_axis_z
        projection := linalg.dot(frame_reference, axis_y)
        axis_z_candidate := third_person.Vec3 {
            frame_reference.x - axis_y.x * projection,
            frame_reference.y - axis_y.y * projection,
            frame_reference.z - axis_y.z * projection,
        }
        if linalg.dot(axis_z_candidate, axis_z_candidate) < .0001 {
            fallback := ring_index > 0 ? previous_axis_x : third_person.Vec3{0, 1, 0}
            if ring_index == 0 && math.abs(axis_y.y) > .90 do fallback = third_person.Vec3{1, 0, 0}
            fallback_projection := linalg.dot(fallback, axis_y)
            axis_z_candidate = {
                fallback.x - axis_y.x * fallback_projection,
                fallback.y - axis_y.y * fallback_projection,
                fallback.z - axis_y.z * fallback_projection,
            }
        }
        axis_z := linalg.normalize0(axis_z_candidate)
        axis_x := linalg.normalize0(linalg.cross(axis_y, axis_z))
        // Projecting the previous radial axis onto the new tangent plane is a
        // discrete parallel transport: ring indices retain their orientation
        // through bends instead of independently choosing a frame/sign.
        previous_axis_x, previous_axis_z = axis_x, axis_z
        for segment in 0 ..< SEGMENTS {
            angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
            cosine, sine := math.cos(angle), math.sin(angle)
            radius := radii[ring_index]
            offset := third_person.Vec3 {
                axis_x.x * cosine * radius + axis_z.x * sine * radius,
                axis_x.y * cosine * radius + axis_z.y * sine * radius,
                axis_x.z * cosine * radius + axis_z.z * sine * radius,
            }
            rings[ring_index][segment] = {
                points[ring_index].x + offset.x,
                points[ring_index].y + offset.y,
                points[ring_index].z + offset.z,
            }
        }
    }

    // Derive normals from the posed tube rather than from the construction
    // frames. Averaging both neighboring rings and radial segments keeps the
    // coat continuous through elbows, wrists, knees, and hocks.
    for ring_index in 0 ..< len(points) {
        previous_ring := max(ring_index - 1, 0)
        next_ring := min(ring_index + 1, len(points) - 1)
        for segment in 0 ..< SEGMENTS {
            previous_segment := (segment + SEGMENTS - 1) % SEGMENTS
            next_segment := (segment + 1) % SEGMENTS
            along := rings[next_ring][segment] - rings[previous_ring][segment]
            around := rings[ring_index][next_segment] - rings[ring_index][previous_segment]
            normals[ring_index][segment] = linalg.normalize0(linalg.cross(along, around))
        }
    }

    for ring_index in 0 ..< len(points) - 1 {
        for segment in 0 ..< SEGMENTS {
            next_segment := (segment + 1) % SEGMENTS
            a, b := rings[ring_index][segment], rings[ring_index][next_segment]
            c, d := rings[ring_index + 1][next_segment], rings[ring_index + 1][segment]
            world_triangle_smooth_lit(
                a,
                d,
                c,
                normals[ring_index][segment],
                normals[ring_index + 1][segment],
                normals[ring_index + 1][next_segment],
                colors[ring_index],
                colors[ring_index + 1],
                colors[ring_index + 1],
            )
            world_triangle_smooth_lit(
                a,
                c,
                b,
                normals[ring_index][segment],
                normals[ring_index + 1][next_segment],
                normals[ring_index][next_segment],
                colors[ring_index],
                colors[ring_index + 1],
                colors[ring_index],
            )
        }
    }
    last := len(points) - 1
    root_normal := linalg.normalize0(points[0] - points[1])
    tip_normal := linalg.normalize0(points[last] - points[last - 1])
    for segment in 0 ..< SEGMENTS {
        next_segment := (segment + 1) % SEGMENTS
        if cap_root {
            world_triangle_smooth_lit(
                points[0],
                rings[0][segment],
                rings[0][next_segment],
                root_normal,
                normals[0][segment],
                normals[0][next_segment],
                colors[0],
                colors[0],
                colors[0],
            )
        }
        world_triangle_smooth_lit(
            points[last],
            rings[last][next_segment],
            rings[last][segment],
            tip_normal,
            normals[last][next_segment],
            normals[last][segment],
            colors[last],
            colors[last],
            colors[last],
        )
    }
}

world_box_between :: proc(a, b, forward: third_person.Vec3, width, depth: f32, color: canvas2d.Color) {
    delta := third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
    length := linalg.length(delta)
    if length <= .0001 do return
    axis_y := third_person.Vec3{delta.x / length, delta.y / length, delta.z / length}
    axis_z := linalg.normalize0(forward)
    axis_x := linalg.cross(axis_y, axis_z)
    axis_x_length := linalg.length(axis_x)
    if axis_x_length <= .0001 {
        axis_x = linalg.cross(axis_y, third_person.Vec3{0, 1, 0})
        axis_x_length = linalg.length(axis_x)
    }
    if axis_x_length > .0001 {
        axis_x = {axis_x.x / axis_x_length, axis_x.y / axis_x_length, axis_x.z / axis_x_length}
    } else {
        axis_x = third_person.Vec3{1, 0, 0}
    }
    center := third_person.Vec3{(a.x + b.x) * .5, (a.y + b.y) * .5, (a.z + b.z) * .5}
    signs := [8][3]f32 {
        {-1, -1, -1},
        {1, -1, -1},
        {1, 1, -1},
        {-1, 1, -1},
        {-1, -1, 1},
        {1, -1, 1},
        {1, 1, 1},
        {-1, 1, 1},
    }
    p: [8]third_person.Vec3
    for index in 0 ..< 8 {
        x := signs[index][0] * width * .5
        y := signs[index][1] * length * .5
        z := signs[index][2] * depth * .5
        p[index] = {
            center.x + axis_x.x * x + axis_y.x * y + axis_z.x * z,
            center.y + axis_x.y * x + axis_y.y * y + axis_z.y * z,
            center.z + axis_x.z * x + axis_y.z * y + axis_z.z * z,
        }
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

world_roof_face_normal :: proc(edge_a, edge_b, ridge_a: third_person.Vec3) -> third_person.Vec3 {
    edge := edge_b - edge_a
    slope := ridge_a - edge_a
    normal := third_person.Vec3 {
        edge.y * slope.z - edge.z * slope.y,
        edge.z * slope.x - edge.x * slope.z,
        edge.x * slope.y - edge.y * slope.x,
    }
    if normal.y < 0 do normal = -normal
    length := math.sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
    if length <= 0.0001 do return {0, 1, 0}
    return normal / length
}

world_roof_offset :: proc(point, normal: third_person.Vec3, amount: f32) -> third_person.Vec3 {
    return point + normal * amount
}

world_roof_surface_y :: #force_inline proc(eave_y, rise, half_width, local_x: f32) -> f32 {
    if half_width <= .0001 do return eave_y
    slope_fraction := 1 - clamp(math.abs(local_x) / half_width, f32(0), f32(1))
    return eave_y + rise * slope_fraction
}

world_roof_long_axis_frame :: #force_inline proc(width, depth, rotation: f32) -> (f32, f32, f32) {
    if width > depth {
        return depth, width, rotation + math.PI * .5
    }
    return width, depth, rotation
}

world_gable_attic_opening_plan :: proc(
    building_width: f32,
    low_gable: bool,
) -> (
    opening_width, opening_height, rise, center_fraction: f32,
    valid: bool,
) {
    rise = building_width * (low_gable ? f32(.24) : f32(.34))
    if rise <= .0001 do return
    center_fraction = low_gable ? f32(.36) : f32(.40)
    opening_height = min(clamp(rise * .25, f32(.75), f32(2.4)), rise * .38)
    frame_margin := f32(.18)
    top_fraction := center_fraction + (opening_height * .5 + frame_margin) / rise
    available_width := building_width * max(f32(0), 1 - top_fraction) * .72
    opening_width = min(clamp(building_width * .12, f32(1.0), f32(2.2)), available_width - frame_margin * 2)
    valid = opening_height >= .65 && opening_width >= .80
    return
}

world_architecture_chimney_flashing :: proc(
    structure: terrain.Structure,
    eave_y, rise, half_roof_width, chimney_local_x, chimney_local_z, chimney_width: f32,
) {
    apron_half := chimney_width * .5 + .24
    local_min_x, local_max_x := chimney_local_x - apron_half, chimney_local_x + apron_half
    local_min_z, local_max_z := chimney_local_z - apron_half, chimney_local_z + apron_half
    a_x, a_z := world_rotate_xz(structure.center_x, structure.center_z, local_min_x, local_min_z, structure.rotation)
    b_x, b_z := world_rotate_xz(structure.center_x, structure.center_z, local_min_x, local_max_z, structure.rotation)
    c_x, c_z := world_rotate_xz(structure.center_x, structure.center_z, local_max_x, local_max_z, structure.rotation)
    d_x, d_z := world_rotate_xz(structure.center_x, structure.center_z, local_max_x, local_min_z, structure.rotation)
    lift := f32(.16)
    a := third_person.Vec3{a_x, world_roof_surface_y(eave_y, rise, half_roof_width, local_min_x) + lift, a_z}
    b := third_person.Vec3{b_x, world_roof_surface_y(eave_y, rise, half_roof_width, local_min_x) + lift, b_z}
    c := third_person.Vec3{c_x, world_roof_surface_y(eave_y, rise, half_roof_width, local_max_x) + lift, c_z}
    d := third_person.Vec3{d_x, world_roof_surface_y(eave_y, rise, half_roof_width, local_max_x) + lift, d_z}
    world_quad(a, b, c, d, {104, 94, 81, 255})
}

// A Greek tile roof reads through its repeated courses: each course runs from
// the lower edge toward the ridge, with small gaps that catch the light.
world_architecture_tile_slope :: proc(
    edge_a, edge_b, ridge_a, ridge_b: third_person.Vec3,
    courses, segments: int,
    palette_seed, pattern_seed: u32,
    reverse_winding := false,
) {
    face_normal := world_roof_face_normal(edge_a, edge_b, ridge_a)
    for course in 0 ..< courses {
        course_start := f32(course) / f32(courses)
        // Leave only a narrow shadow joint between overlapping courses. The
        // former 22% gap made each tile read as a large floating roof panel.
        course_end := min(course_start + .90 / f32(courses), 1)
        // Keep the decorative courses a constant distance in front of the
        // weatherproof plane. Offsetting in world Y makes the actual gap vary
        // with roof pitch and lets hip-face overlays intersect at their seams.
        relief := .12 + f32(course % 2) * .012
        for segment in 0 ..< segments {
            segment_start := f32(segment) / f32(segments)
            segment_end := f32(segment + 1) / f32(segments)
            // Offset alternate courses so the vertical joins do not line up.
            offset := course % 2 == 0 ? 0 : .035 / f32(segments)
            segment_start = clamp(segment_start + offset, 0, 1)
            segment_end = clamp(segment_end + offset, 0, 1)

            outer_a := linalg.lerp(edge_a, edge_b, segment_start)
            outer_b := linalg.lerp(edge_a, edge_b, segment_end)
            // Preserve the segment interval as it climbs the slope. Mapping
            // every segment to both full ridge endpoints makes neighboring
            // tiles fan across one another, producing coplanar overlap and
            // severe z-fighting near the ridge.
            ridge_segment_a := linalg.lerp(ridge_a, ridge_b, segment_start)
            ridge_segment_b := linalg.lerp(ridge_a, ridge_b, segment_end)
            inner_a := linalg.lerp(outer_a, ridge_segment_a, course_start)
            inner_b := linalg.lerp(outer_b, ridge_segment_b, course_start)
            next_a := linalg.lerp(outer_a, ridge_segment_a, course_end)
            next_b := linalg.lerp(outer_b, ridge_segment_b, course_end)
            inner_a = world_roof_offset(inner_a, face_normal, relief)
            inner_b = world_roof_offset(inner_b, face_normal, relief)
            next_a = world_roof_offset(next_a, face_normal, relief)
            next_b = world_roof_offset(next_b, face_normal, relief)

            tone := architecture.architecture_roof_tile_tone(pattern_seed, course, segment)
            tile_bytes := architecture.architecture_roof_tile_color(palette_seed, tone)
            tile := canvas2d.Color{tile_bytes[0], tile_bytes[1], tile_bytes[2], tile_bytes[3]}
            if reverse_winding {
                world_quad(inner_a, next_a, next_b, inner_b, tile)
            } else {
                world_quad(inner_a, inner_b, next_b, next_a, tile)
            }
        }
    }

    // Raised cover rolls run continuously down the fall line and turn the
    // colored course grid into a recognizable barrel-tile roof. A small
    // number of stylized rolls is much cheaper and calmer at game scale than
    // modeling every pan and cap tile individually.
    slope_length := linalg.length(ridge_a - edge_a)
    roll_radius := clamp(slope_length * .008, f32(.055), f32(.095))
    roll_relief := .12 + roll_radius * .55
    roll_bytes := architecture.architecture_roof_tile_color(palette_seed, 2)
    roll_color := canvas2d.Color{roll_bytes[0], roll_bytes[1], roll_bytes[2], roll_bytes[3]}
    // Face-edge seams already receive fascia or hip caps; adding a roll there
    // doubles the geometry and produces a bright outline around the roof.
    for boundary in 1 ..< segments {
        across := f32(boundary) / f32(segments)
        eave_point := linalg.lerp(edge_a, edge_b, across)
        ridge_point := linalg.lerp(ridge_a, ridge_b, across)
        lift := face_normal * roll_relief
        world_tube_between(eave_point + lift, ridge_point + lift, face_normal, roll_radius, roll_radius, roll_color)
    }
}

world_architecture_roof_cap_run :: proc(
    a, b: third_person.Vec3,
    radius: f32,
    palette_seed, pattern_seed: u32,
    detailed := true,
) {
    run_length := linalg.length(b - a)
    if run_length <= .001 do return
    // At medium LOD the run is below the size where individual overlaps are
    // visible. Keep one tube for the silhouette and reserve the segmented
    // cap-tile construction for near roofs.
    cap_count := 1
    if detailed {
        cap_count = clamp(int(math.round(f64(run_length / 1.35))), 3, 14)
    }
    for cap_index in 0 ..< cap_count {
        start_t := f32(cap_index) / f32(cap_count)
        // Traditional cap tiles overlap the next unit rather than meeting at
        // a perfectly machined seam. The overlap also keeps the weatherproof
        // roof plane hidden between the short cylindrical pieces.
        end_t := min(f32(cap_index + 1) / f32(cap_count) + .08 / f32(cap_count), f32(1))
        cap_a := linalg.lerp(a, b, start_t)
        cap_b := linalg.lerp(a, b, end_t)
        tone := architecture.architecture_roof_tile_tone(pattern_seed, 0, cap_index)
        cap_bytes := architecture.architecture_roof_tile_color(palette_seed, tone)
        cap_color := canvas2d.Color{cap_bytes[0], cap_bytes[1], cap_bytes[2], cap_bytes[3]}
        world_tube_between(cap_a, cap_b, {0, 1, 0}, radius, radius, cap_color)
    }
}

world_architecture_pyramid_cap :: proc(
    center_x, center_z, base_y, width, depth, rotation, tip_height: f32,
    color: canvas2d.Color,
) {
    front_left_x, front_left_z := world_rotate_xz(center_x, center_z, -width * .5, -depth * .5, rotation)
    front_right_x, front_right_z := world_rotate_xz(center_x, center_z, width * .5, -depth * .5, rotation)
    back_right_x, back_right_z := world_rotate_xz(center_x, center_z, width * .5, depth * .5, rotation)
    back_left_x, back_left_z := world_rotate_xz(center_x, center_z, -width * .5, depth * .5, rotation)
    front_left := third_person.Vec3{front_left_x, base_y, front_left_z}
    front_right := third_person.Vec3{front_right_x, base_y, front_right_z}
    back_right := third_person.Vec3{back_right_x, base_y, back_right_z}
    back_left := third_person.Vec3{back_left_x, base_y, back_left_z}
    tip := third_person.Vec3{center_x, base_y + tip_height, center_z}
    world_triangle(front_left, tip, front_right, color)
    world_triangle(front_right, tip, back_right, formation_face_color(color, math.PI * .5, 0))
    world_triangle(back_right, tip, back_left, formation_face_color(color, math.PI, 0))
    world_triangle(back_left, tip, front_left, formation_face_color(color, math.PI * 1.5, 0))
}

world_architecture_tile_face :: proc(edge_a, edge_b, ridge: third_person.Vec3, courses, segments: int, seed: u32) {
    world_architecture_tile_slope(edge_a, edge_b, ridge, ridge, courses, segments, seed, seed)
}

world_architecture_roof_style :: proc(structure: terrain.Structure) -> architecture.Roof_Style {
    identity := architecture.architecture_resolve_legacy_identity(structure)
    if identity.region == .Aegean && !buildings.is_landmark(identity) {
        return .Parapet
    }
    if identity.region == .Adriatic && (identity.archetype == .Farmstead || identity.archetype == .Barn_Granary) {
        return .Low_Gable
    }
    return architecture.roof_style_for_seed(structure.seed)
}
