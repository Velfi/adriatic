package main
import "core:math"

import mouse_paws "../packages/mouse_paws"
import third_person "zelda_engine:third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_surface_paw_pad :: proc(
    center, normal: third_person.Vec3,
    radius_x, radius_z, height, rotation, compression: f32,
    color: canvas2d.Color,
) {
    up := linalg.normalize0(normal)
    if linalg.dot(up, up) < .5 do up = {0, 1, 0}
    forward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
    forward -= up * linalg.dot(forward, up)
    forward = linalg.normalize0(forward)
    if linalg.dot(forward, forward) < .5 do forward = {0, 0, 1}
    right := linalg.normalize0(linalg.cross(up, forward))
    scale := mouse_paws.pad_scale(compression)
    scaled_radius_x := radius_x * scale.x
    scaled_height := height * scale.y
    scaled_radius_z := radius_z * scale.z
    SEGMENTS :: 10
    bottom, top: [SEGMENTS]third_person.Vec3
    half_height := scaled_height * .5
    for segment in 0 ..< SEGMENTS {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
        radial := right * (math.cos(angle) * scaled_radius_x) + forward * (math.sin(angle) * scaled_radius_z)
        bottom[segment] = center + radial - up * half_height
        top[segment] = center + radial + up * half_height
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_quad(bottom[segment], top[segment], top[next], bottom[next], color)
        world_triangle(center - up * half_height, bottom[segment], bottom[next], color)
        world_triangle(center + up * half_height, top[next], top[segment], color)
    }
}

world_vertical_disc_rotated :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, depth, rotation: f32,
    color: canvas2d.Color,
    material_kind: World_Material_Kind = .BRDF,
) {
    SEGMENTS :: 12
    back, front: [SEGMENTS]third_person.Vec3
    half_depth := depth * .5
    back_x, back_z := world_rotate_xz(center.x, center.z, 0, -half_depth, rotation)
    front_x, front_z := world_rotate_xz(center.x, center.z, 0, half_depth, rotation)
    back_center := third_person.Vec3{back_x, center.y, back_z}
    front_center := third_person.Vec3{front_x, center.y, front_z}
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        local_x := math.cos(angle) * radius_x
        local_y := math.sin(angle) * radius_y
        back_world_x, back_world_z := world_rotate_xz(center.x, center.z, local_x, -half_depth, rotation)
        front_world_x, front_world_z := world_rotate_xz(center.x, center.z, local_x, half_depth, rotation)
        back[segment] = {back_world_x, center.y + local_y, back_world_z}
        front[segment] = {front_world_x, center.y + local_y, front_world_z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle_material(back_center, back[next], back[segment], color, material_kind)
        world_triangle_material(front_center, front[segment], front[next], color, material_kind)
        world_quad_material(back[segment], back[next], front[next], front[segment], color, material_kind)
    }
}

world_ellipsoid_rotated :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, radius_z, rotation: f32,
    color: canvas2d.Color,
    material_kind: World_Material_Kind = .Eye,
) {
    LATITUDE_SEGMENTS :: 6
    LONGITUDE_SEGMENTS :: 10
    points: [LATITUDE_SEGMENTS + 1][LONGITUDE_SEGMENTS]third_person.Vec3
    normals: [LATITUDE_SEGMENTS + 1][LONGITUDE_SEGMENTS]third_person.Vec3
    for latitude in 0 ..= LATITUDE_SEGMENTS {
        latitude_angle := -math.PI * .5 + f32(latitude) * math.PI / f32(LATITUDE_SEGMENTS)
        latitude_radius := math.cos(latitude_angle)
        local_y := math.sin(latitude_angle) * radius_y
        for longitude in 0 ..< LONGITUDE_SEGMENTS {
            longitude_angle := f32(longitude) * math.PI * 2 / f32(LONGITUDE_SEGMENTS)
            local_x := math.cos(longitude_angle) * latitude_radius * radius_x
            local_z := math.sin(longitude_angle) * latitude_radius * radius_z
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            points[latitude][longitude] = {world_x, center.y + local_y, world_z}
            local_normal := linalg.normalize0(
                third_person.Vec3 {
                    local_x / max(radius_x * radius_x, f32(.000001)),
                    local_y / max(radius_y * radius_y, f32(.000001)),
                    local_z / max(radius_z * radius_z, f32(.000001)),
                },
            )
            normal_x, normal_z := world_rotate_xz(0, 0, local_normal.x, local_normal.z, rotation)
            normals[latitude][longitude] = {normal_x, local_normal.y, normal_z}
        }
    }
    for latitude in 0 ..< LATITUDE_SEGMENTS {
        for longitude in 0 ..< LONGITUDE_SEGMENTS {
            next := (longitude + 1) % LONGITUDE_SEGMENTS
            vertex_coordinates := [6][2]int {
                {latitude, longitude},
                {latitude + 1, longitude},
                {latitude + 1, next},
                {latitude, longitude},
                {latitude + 1, next},
                {latitude, next},
            }
            for coordinate in vertex_coordinates {
                point_latitude, point_longitude := coordinate[0], coordinate[1]
                vertex := world_eye_vertex(
                    points[point_latitude][point_longitude],
                    color,
                    normals[point_latitude][point_longitude],
                )
                vertex.kind = material_kind
                if material_kind == .BRDF do vertex.material = {0, .9}
                if material_kind == .Acorn {
                    vertex.uv = {
                        f32(point_longitude) / f32(LONGITUDE_SEGMENTS),
                        f32(point_latitude) / f32(LATITUDE_SEGMENTS),
                    }
                    // Unwrap triangles that cross the longitude seam instead
                    // of interpolating through the entire texture domain.
                    if longitude == LONGITUDE_SEGMENTS - 1 && point_longitude == 0 {
                        vertex.uv[0] = 1
                    }
                }
                append(&world_renderer.vertices, vertex)
            }
        }
    }
}

// A softly faceted, material-backed ellipsoid for cloth and other matte props.
// Flat face normals preserve the tailored low-poly shape while high roughness
// avoids the hard wet-looking highlights used by the specialized eye material.
world_ellipsoid_matte_oriented :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, radius_z, rotation, roll: f32,
    color: canvas2d.Color,
) {
    LATITUDE_SEGMENTS :: 6
    LONGITUDE_SEGMENTS :: 10
    points: [LATITUDE_SEGMENTS + 1][LONGITUDE_SEGMENTS]third_person.Vec3
    roll_cos, roll_sin := math.cos(roll), math.sin(roll)
    for latitude in 0 ..= LATITUDE_SEGMENTS {
        latitude_angle := -math.PI * .5 + f32(latitude) * math.PI / f32(LATITUDE_SEGMENTS)
        latitude_radius := math.cos(latitude_angle)
        local_y := math.sin(latitude_angle) * radius_y
        for longitude in 0 ..< LONGITUDE_SEGMENTS {
            longitude_angle := f32(longitude) * math.PI * 2 / f32(LONGITUDE_SEGMENTS)
            local_x := math.cos(longitude_angle) * latitude_radius * radius_x
            local_z := math.sin(longitude_angle) * latitude_radius * radius_z
            rolled_x := local_x * roll_cos - local_y * roll_sin
            rolled_y := local_x * roll_sin + local_y * roll_cos
            world_x, world_z := world_rotate_xz(center.x, center.z, rolled_x, local_z, rotation)
            points[latitude][longitude] = {world_x, center.y + rolled_y, world_z}
        }
    }
    for latitude in 0 ..< LATITUDE_SEGMENTS {
        for longitude in 0 ..< LONGITUDE_SEGMENTS {
            next := (longitude + 1) % LONGITUDE_SEGMENTS
            world_triangle(
                points[latitude][longitude],
                points[latitude + 1][longitude],
                points[latitude + 1][next],
                color,
            )
            world_triangle(points[latitude][longitude], points[latitude + 1][next], points[latitude][next], color)
        }
    }
}

world_ellipsoid_matte_rotated :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, radius_z, rotation: f32,
    color: canvas2d.Color,
) {
    world_ellipsoid_matte_oriented(center, radius_x, radius_y, radius_z, rotation, 0, color)
}

// One closed, connected shell for the bottle-cap hat. The alternating outer
// radius is part of the hull itself, so the crimped edge no longer depends on
// detached blocks. UVs drive the pressed-metal finish in the world shader.
world_bottle_cap_hull :: proc(center: third_person.Vec3, rotation: f32, color: canvas2d.Color) {
    // Forty-two vertices give the perimeter twenty-one crown-cap teeth.
    SEGMENTS :: 42
    RING_COUNT :: 7
    // Keep the top broad and almost planar. The former domed transition made
    // the cap read as a soft beret despite its ribbed edge.
    heights := [RING_COUNT]f32{-.060, -.045, .010, .045, .061, .066, .068}
    radii_x := [RING_COUNT]f32{.205, .265, .258, .232, .204, .115, 0}
    radii_z := [RING_COUNT]f32{.185, .242, .235, .210, .184, .104, 0}
    rings: [RING_COUNT][SEGMENTS]third_person.Vec3
    normals: [RING_COUNT][SEGMENTS]third_person.Vec3
    uvs: [RING_COUNT][SEGMENTS][2]f32
    for ring_index in 0 ..< RING_COUNT {
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            // Twenty-one sharp flutes around the rolled skirt, carried by the
            // first three rings so each crimp remains joined to the crown.
            crimp := ring_index <= 2 ? (1 + math.cos(angle * 21)) * .5 : f32(0)
            crimp_scale := 1 + crimp * (ring_index == 1 ? f32(.075) : f32(.032))
            local_x := math.cos(angle) * radii_x[ring_index] * crimp_scale
            local_z := math.sin(angle) * radii_z[ring_index] * crimp_scale
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            rings[ring_index][segment] = {world_x, center.y + heights[ring_index], world_z}
            uvs[ring_index][segment] = {.5 + local_x / (.265 * 2), .5 + local_z / (.242 * 2)}
            local_normal := linalg.normalize0(
                [3]f32 {
                    local_x / max(radii_x[ring_index] * radii_x[ring_index], f32(.000001)),
                    ring_index >= 4 ? f32(1) : f32(.18),
                    local_z / max(radii_z[ring_index] * radii_z[ring_index], f32(.000001)),
                },
            )
            normal_x, normal_z := world_rotate_xz(0, 0, local_normal.x, local_normal.z, rotation)
            normals[ring_index][segment] = {normal_x, local_normal.y, normal_z}
        }
    }
    for ring_index in 0 ..< RING_COUNT - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            coordinates := [6][2]int {
                {ring_index, segment},
                {ring_index + 1, segment},
                {ring_index + 1, next},
                {ring_index, segment},
                {ring_index + 1, next},
                {ring_index, next},
            }
            for coordinate in coordinates {
                ring, point := coordinate[0], coordinate[1]
                vertex := world_eye_vertex(rings[ring][point], color, normals[ring][point])
                vertex.kind = .Bottle_Cap
                vertex.uv = uvs[ring][point]
                vertex.material[0] = f32(ring) / f32(RING_COUNT - 1)
                append(&world_renderer.vertices, vertex)
            }
        }
    }
    bottom := third_person.Vec3{center.x, center.y + heights[0], center.z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        bottom_coordinates := [3]int{segment, next, -1}
        for coordinate in bottom_coordinates {
            point := coordinate < 0 ? bottom : rings[0][coordinate]
            vertex := world_eye_vertex(point, color, {0, -1, 0})
            vertex.kind = .Bottle_Cap
            vertex.uv =
                coordinate < 0 ? [2]f32{.5, 0} : [2]f32{.5 + math.cos(f32(coordinate) * math.PI * 2 / f32(SEGMENTS)) * .5, .5 + math.sin(f32(coordinate) * math.PI * 2 / f32(SEGMENTS)) * .5}
            vertex.material[0] = 0
            append(&world_renderer.vertices, vertex)
        }
    }
}

// A single connected felt shell for the Tyrolean hat. Its radial profile
// travels from the closed underside, around the brim, and continuously up the
// tapered crown; every visible felt contour therefore belongs to one hull.
world_alpine_hat_hull :: proc(center: third_person.Vec3, rotation: f32, felt_dark, felt, felt_light: canvas2d.Color) {
    SEGMENTS :: 14
    RING_COUNT :: 7
    heights := [RING_COUNT]f32{-.045, -.020, .010, .045, .135, .205, .225}
    radii_x := [RING_COUNT]f32{.305, .325, .238, .225, .195, .148, .112}
    radii_z := [RING_COUNT]f32{.215, .235, .190, .180, .150, .112, .080}
    offsets_x := [RING_COUNT]f32{0, 0, 0, 0, -.010, -.030, -.040}
    offsets_z := [RING_COUNT]f32{0, .010, 0, -.005, -.010, 0, .012}
    colors := [RING_COUNT]canvas2d.Color{felt_dark, felt_dark, felt, felt, felt, felt_light, felt_light}
    rings: [RING_COUNT][SEGMENTS]third_person.Vec3
    for ring_index in 0 ..< RING_COUNT {
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            local_x := offsets_x[ring_index] + math.cos(angle) * radii_x[ring_index]
            local_z := offsets_z[ring_index] + math.sin(angle) * radii_z[ring_index]
            ring_height := heights[ring_index]
            if ring_index <= 1 {
                // Lift only the feather side of both brim surfaces. Keeping
                // the underside and upper edge together preserves hull
                // thickness while breaking the perfectly level bowler line.
                ring_height += max(math.cos(angle), f32(0)) * .030
            }
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            rings[ring_index][segment] = {world_x, center.y + ring_height, world_z}
        }
    }
    for ring_index in 0 ..< RING_COUNT - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            world_triangle_colored(
                rings[ring_index][segment],
                rings[ring_index + 1][segment],
                rings[ring_index + 1][next],
                colors[ring_index],
                colors[ring_index + 1],
                colors[ring_index + 1],
            )
            world_triangle_colored(
                rings[ring_index][segment],
                rings[ring_index + 1][next],
                rings[ring_index][next],
                colors[ring_index],
                colors[ring_index + 1],
                colors[ring_index],
            )
        }
    }
    bottom_x, bottom_z := world_rotate_xz(center.x, center.z, 0, 0, rotation)
    top_x, top_z := world_rotate_xz(
        center.x,
        center.z,
        offsets_x[RING_COUNT - 1] - .015,
        offsets_z[RING_COUNT - 1],
        rotation,
    )
    bottom_center := third_person.Vec3{bottom_x, center.y + heights[0], bottom_z}
    // Sink the cap center below its final ring to press a shallow crease into
    // the crown while retaining one continuous watertight shell.
    top_center := third_person.Vec3{top_x, center.y + heights[RING_COUNT - 1] - .018, top_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(bottom_center, rings[0][next], rings[0][segment], felt_dark)
        world_triangle(top_center, rings[RING_COUNT - 1][segment], rings[RING_COUNT - 1][next], felt_light)
    }
}

// One closed cloth shell for the flat cap. The first rings travel from the
// fitted underside out around the asymmetric forward peak; successive rings
// pull back over the skull into the low crown. Crown and brim therefore share
// vertices instead of intersecting as separate primitives.
world_flat_cap_hull :: proc(
    center: third_person.Vec3,
    rotation: f32,
    tweed_dark, tweed, tweed_front, tweed_light: canvas2d.Color,
) {
    SEGMENTS :: 18
    RING_COUNT :: 7
    heights := [RING_COUNT]f32{-.045, -.030, -.012, 0, .055, .100, .122}
    radii_x := [RING_COUNT]f32{.190, .205, .205, .235, .238, .205, .120}
    radii_z := [RING_COUNT]f32{.150, .205, .205, .205, .200, .160, .090}
    offsets_z := [RING_COUNT]f32{-.020, .090, .090, -.025, -.045, -.055, -.060}
    front_drop := [RING_COUNT]f32{0, .002, .004, .010, .024, .034, .025}
    colors := [RING_COUNT]canvas2d.Color{tweed_dark, tweed_dark, tweed_front, tweed_front, tweed, tweed, tweed_light}

    rings: [RING_COUNT][SEGMENTS]third_person.Vec3
    vertex_colors: [RING_COUNT][SEGMENTS]canvas2d.Color
    for ring_index in 0 ..< RING_COUNT {
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            local_x := math.cos(angle) * radii_x[ring_index]
            local_z := offsets_z[ring_index] + math.sin(angle) * radii_z[ring_index]
            local_y := heights[ring_index] - max(math.sin(angle), 0) * front_drop[ring_index]
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            rings[ring_index][segment] = {world_x, center.y + local_y, world_z}
            vertex_colors[ring_index][segment] = colors[ring_index]
            if ring_index >= 3 {
                // Eighteen radial samples form six broad cloth panels. The
                // restrained alternating value is visible at gameplay scale
                // without turning the tweed into a striped helmet.
                panel := (segment / 3) % 2
                panel_tint := panel == 0 ? tweed_light : tweed_dark
                vertex_colors[ring_index][segment] = color_lerp(colors[ring_index], panel_tint, .10)
            }
        }
    }

    for ring_index in 0 ..< RING_COUNT - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            world_triangle_colored(
                rings[ring_index][segment],
                rings[ring_index + 1][segment],
                rings[ring_index + 1][next],
                vertex_colors[ring_index][segment],
                vertex_colors[ring_index + 1][segment],
                vertex_colors[ring_index + 1][next],
            )
            world_triangle_colored(
                rings[ring_index][segment],
                rings[ring_index + 1][next],
                rings[ring_index][next],
                vertex_colors[ring_index][segment],
                vertex_colors[ring_index + 1][next],
                vertex_colors[ring_index][next],
            )
        }
    }

    bottom_x, bottom_z := world_rotate_xz(center.x, center.z, 0, offsets_z[0], rotation)
    top_x, top_z := world_rotate_xz(center.x, center.z, 0, offsets_z[RING_COUNT - 1], rotation)
    bottom_center := third_person.Vec3{bottom_x, center.y + heights[0], bottom_z}
    // A shallow center depression keeps the non-planar crown fan outward
    // facing after the forward drape and gives the cloth a tailored set.
    top_center := third_person.Vec3{top_x, center.y + heights[RING_COUNT - 1] - .035, top_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(bottom_center, rings[0][next], rings[0][segment], tweed_dark)
        world_triangle_colored(
            top_center,
            rings[RING_COUNT - 1][segment],
            rings[RING_COUNT - 1][next],
            tweed,
            vertex_colors[RING_COUNT - 1][segment],
            vertex_colors[RING_COUNT - 1][next],
        )
    }
}

// One continuous cloth shell for the sailor hat. The profile travels from the
// fitted underside, around the upturned bucket brim, and inward over the crown.
// UVs follow that profile so the shader's stripes and weave remain attached to
// the fabric instead of being represented by stacked geometry.
world_sailor_hat_hull :: proc(center: third_person.Vec3, rotation: f32, color: canvas2d.Color) {
    SEGMENTS :: 24
    RING_COUNT :: 8
    heights := [RING_COUNT]f32{-.050, -.036, .020, .052, .036, .112, .174, .192}
    radii_x := [RING_COUNT]f32{.150, .248, .280, .252, .205, .196, .168, .112}
    radii_z := [RING_COUNT]f32{.120, .195, .220, .202, .162, .156, .132, .086}
    offsets_z := [RING_COUNT]f32{-.012, 0, .004, 0, -.006, -.012, -.018, -.022}
    // Profile-distance UVs keep the two fabric stripes a consistent physical
    // width as the brim rolls upward into the bucket crown.
    profile_v := [RING_COUNT]f32{0, .16, .30, .40, .47, .66, .88, .96}

    rings: [RING_COUNT][SEGMENTS]third_person.Vec3
    normals: [RING_COUNT][SEGMENTS]third_person.Vec3
    uvs: [RING_COUNT][SEGMENTS][2]f32
    for ring_index in 0 ..< RING_COUNT {
        previous := max(ring_index - 1, 0)
        following := min(ring_index + 1, RING_COUNT - 1)
        height_delta := heights[following] - heights[previous]
        radius_delta := (radii_x[following] - radii_x[previous] + radii_z[following] - radii_z[previous]) * .5
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            local_x := math.cos(angle) * radii_x[ring_index]
            local_z := offsets_z[ring_index] + math.sin(angle) * radii_z[ring_index]
            // A slightly higher side and rear edge gives the brim the jaunty,
            // hand-shaped rise of a soft sailor bucket rather than a rigid bowl.
            brim_lift := f32(0)
            if ring_index == 2 || ring_index == 3 {
                brim_lift = (.5 - math.sin(angle) * .5) * .018 + math.abs(math.cos(angle)) * .010
            }
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            rings[ring_index][segment] = {world_x, center.y + heights[ring_index] + brim_lift, world_z}

            radial_y := -radius_delta / max(math.abs(height_delta), f32(.025))
            local_normal := linalg.normalize0([3]f32{math.cos(angle), radial_y, math.sin(angle)})
            normal_x, normal_z := world_rotate_xz(0, 0, local_normal.x, local_normal.z, rotation)
            normals[ring_index][segment] = {normal_x, local_normal.y, normal_z}
            uvs[ring_index][segment] = {f32(segment) / f32(SEGMENTS), profile_v[ring_index]}
        }
    }

    for ring_index in 0 ..< RING_COUNT - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            coordinates := [6][2]int {
                {ring_index, segment},
                {ring_index + 1, segment},
                {ring_index + 1, next},
                {ring_index, segment},
                {ring_index + 1, next},
                {ring_index, next},
            }
            for coordinate in coordinates {
                ring, point := coordinate[0], coordinate[1]
                vertex := world_eye_vertex(rings[ring][point], color, normals[ring][point])
                vertex.kind = .Sailor_Hat
                vertex.uv = uvs[ring][point]
                append(&world_renderer.vertices, vertex)
            }
        }
    }

    bottom := third_person.Vec3{center.x, center.y + heights[0], center.z + offsets_z[0]}
    top_x, top_z := world_rotate_xz(center.x, center.z, 0, offsets_z[RING_COUNT - 1], rotation)
    top := third_person.Vec3{top_x, center.y + heights[RING_COUNT - 1] - .012, top_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        bottom_points := [3]int{-1, next, segment}
        for point_index in bottom_points {
            point := point_index < 0 ? bottom : rings[0][point_index]
            vertex := world_eye_vertex(point, color, {0, -1, 0})
            vertex.kind = .Sailor_Hat
            vertex.uv = point_index < 0 ? [2]f32{.5, 0} : uvs[0][point_index]
            append(&world_renderer.vertices, vertex)
        }
        top_points := [3]int{-1, segment, next}
        for point_index in top_points {
            point := point_index < 0 ? top : rings[RING_COUNT - 1][point_index]
            vertex := world_eye_vertex(point, color, {0, 1, 0})
            vertex.kind = .Sailor_Hat
            vertex.uv = point_index < 0 ? [2]f32{.5, 1} : [2]f32{f32(point_index) / f32(SEGMENTS), 1}
            append(&world_renderer.vertices, vertex)
        }
    }
}

// A closed, pointed feather vane. The outline supplies the taper and swept
// tip; shallow extrusion keeps it readable from both front and profile views.
world_alpine_feather_hull :: proc(center: third_person.Vec3, rotation: f32, feather, feather_light: canvas2d.Color) {
    POINT_COUNT :: 8
    outline := [POINT_COUNT][2]f32 {
        {-.060, -.160},
        {-.075, -.075},
        {-.055, .035},
        {-.020, .125},
        {.030, .155},
        {.042, .080},
        {.032, -.025},
        {-.015, -.125},
    }
    depths := [POINT_COUNT]f32{.008, .026, .040, .030, .004, .024, .040, .028}
    back, front: [POINT_COUNT]third_person.Vec3
    back_center := center
    front_center := center
    for index in 0 ..< POINT_COUNT {
        back_world_x, back_world_z := world_rotate_xz(center.x, center.z, outline[index][0], -depths[index], rotation)
        front_world_x, front_world_z := world_rotate_xz(center.x, center.z, outline[index][0], depths[index], rotation)
        back[index] = {back_world_x, center.y + outline[index][1], back_world_z}
        front[index] = {front_world_x, center.y + outline[index][1], front_world_z}
    }
    for index in 0 ..< POINT_COUNT {
        next := (index + 1) % POINT_COUNT
        world_triangle(back_center, back[next], back[index], feather)
        world_triangle(front_center, front[index], front[next], feather_light)
        world_quad(back[index], back[next], front[next], front[index], feather)
    }
}

world_tapered_disc_depth_rotated :: proc(
    center: third_person.Vec3,
    back_radius_x, back_radius_y, front_radius_x, front_radius_y, depth, rotation: f32,
    color: canvas2d.Color,
) {
    SEGMENTS :: 12
    back, front: [SEGMENTS]third_person.Vec3
    half_depth := depth * .5
    back_x, back_z := world_rotate_xz(center.x, center.z, 0, -half_depth, rotation)
    front_x, front_z := world_rotate_xz(center.x, center.z, 0, half_depth, rotation)
    back_center := third_person.Vec3{back_x, center.y, back_z}
    front_center := third_person.Vec3{front_x, center.y, front_z}
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        cosine, sine := math.cos(angle), math.sin(angle)
        back_world_x, back_world_z := world_rotate_xz(
            center.x,
            center.z,
            cosine * back_radius_x,
            -half_depth,
            rotation,
        )
        front_world_x, front_world_z := world_rotate_xz(
            center.x,
            center.z,
            cosine * front_radius_x,
            half_depth,
            rotation,
        )
        back[segment] = {back_world_x, center.y + sine * back_radius_y, back_world_z}
        front[segment] = {front_world_x, center.y + sine * front_radius_y, front_world_z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(back_center, back[next], back[segment], color)
        world_triangle(front_center, front[segment], front[next], color)
        world_quad(back[segment], back[next], front[next], front[segment], color)
    }
}

world_tube_between :: proc(a, b, forward: third_person.Vec3, radius_x, radius_z: f32, color: canvas2d.Color) {
    SEGMENTS :: 8
    delta := third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
    length := linalg.length(delta)
    if length <= .0001 do return
    axis_y := third_person.Vec3{delta.x / length, delta.y / length, delta.z / length}
    reference := linalg.normalize0(forward)
    projection := linalg.dot(reference, axis_y)
    axis_z_candidate := third_person.Vec3 {
        reference.x - axis_y.x * projection,
        reference.y - axis_y.y * projection,
        reference.z - axis_y.z * projection,
    }
    // Tail links often point exactly opposite model-forward. In that case
    // Gram-Schmidt with `forward` produces a zero radial axis and collapses
    // the tube into invisible, zero-area triangles. Choose a stable fallback
    // reference for any collinear segment.
    if linalg.dot(axis_z_candidate, axis_z_candidate) < .0001 {
        fallback := third_person.Vec3{0, 1, 0}
        if math.abs(axis_y.y) > .90 do fallback = third_person.Vec3{1, 0, 0}
        fallback_projection := linalg.dot(fallback, axis_y)
        axis_z_candidate = {
            fallback.x - axis_y.x * fallback_projection,
            fallback.y - axis_y.y * fallback_projection,
            fallback.z - axis_y.z * fallback_projection,
        }
    }
    axis_z := linalg.normalize0(axis_z_candidate)
    axis_x := linalg.normalize0(linalg.cross(axis_y, axis_z))
    ring_a, ring_b: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
        x, z := math.cos(angle) * radius_x, math.sin(angle) * radius_z
        offset := third_person.Vec3 {
            axis_x.x * x + axis_z.x * z,
            axis_x.y * x + axis_z.y * z,
            axis_x.z * x + axis_z.z * z,
        }
        ring_a[segment] = {a.x + offset.x, a.y + offset.y, a.z + offset.z}
        ring_b[segment] = {b.x + offset.x, b.y + offset.y, b.z + offset.z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(a, ring_a[segment], ring_a[next], color)
        world_triangle(b, ring_b[next], ring_b[segment], color)
        world_quad(ring_a[segment], ring_b[segment], ring_b[next], ring_a[next], color)
    }
}
