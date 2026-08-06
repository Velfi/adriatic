package main
import "core:math"

import architecture "../packages/architecture"
import facade_windows "../packages/facade_windows"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

// Shared weathered architectural metal. Its moderate response gives exterior
// ironwork a readable highlight without making aged or painted pieces chrome.
world_metal_box_rotated :: proc(
    center: third_person.Vec3,
    size: third_person.Vec3,
    rotation: f32,
    color: canvas2d.Color,
    metallic: f32 = .68,
    roughness: f32 = .48,
) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad_lit(p[0], p[3], p[2], p[1], color, metallic, roughness)
    world_quad_lit(p[4], p[5], p[6], p[7], color, metallic, roughness)
    world_quad_lit(p[0], p[4], p[7], p[3], color, metallic, roughness)
    world_quad_lit(p[1], p[2], p[6], p[5], color, metallic, roughness)
    world_quad_lit(p[3], p[7], p[6], p[2], color, metallic, roughness)
    world_quad_lit(p[0], p[1], p[5], p[4], color, metallic, roughness)
}

@(no_instrumentation)
world_quad_emissive_fixture :: #force_inline proc(
    a, b, c, d: third_person.Vec3,
    color: canvas2d.Color,
    fixture_kind: f32,
) {
    vertices := [6]World_Vertex {
        world_vertex(a, color),
        world_vertex(b, color),
        world_vertex(c, color),
        world_vertex(a, color),
        world_vertex(c, color),
        world_vertex(d, color),
    }
    uvs := [6][2]f32{{0, 1}, {1, 1}, {1, 0}, {0, 1}, {1, 0}, {0, 0}}
    for &vertex, index in vertices {
        vertex.kind = .Emissive
        vertex.material = {fixture_kind, 0}
        vertex.uv = uvs[index]
    }
    append(&world_renderer.vertices, ..vertices[:])
}

world_emissive_fixture_box :: proc(
    center: third_person.Vec3,
    size: third_person.Vec3,
    rotation: f32,
    color: canvas2d.Color,
    fixture_kind: f32,
) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad_emissive_fixture(p[0], p[3], p[2], p[1], color, fixture_kind)
    world_quad_emissive_fixture(p[4], p[5], p[6], p[7], color, fixture_kind)
    world_quad_emissive_fixture(p[0], p[4], p[7], p[3], color, fixture_kind)
    world_quad_emissive_fixture(p[1], p[2], p[6], p[5], color, fixture_kind)
    world_quad_emissive_fixture(p[3], p[7], p[6], p[2], color, fixture_kind)
    world_quad_emissive_fixture(p[0], p[1], p[5], p[4], color, fixture_kind)
}

world_glass_panel :: proc(
    center: third_person.Vec3,
    width, height, rotation: f32,
    color: canvas2d.Color,
    interior_light: f32 = 0,
    interior_room: f32 = 0,
) {
    half_width, half_height := width * .5, height * .5
    cosine, sine := f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))
    right := third_person.Vec3{cosine, 0, sine}
    up := third_person.Vec3{0, 1, 0}
    normal := third_person.Vec3{-sine, 0, cosine}
    // Window reveals are shallow boxes whose outward face sits slightly
    // beyond their center. Keep the opaque glass plane in front of that face
    // so residential panes are not hidden by the reveal depth surface.
    surface_center := center + normal * .035
    a := surface_center - right * half_width - up * half_height
    b := surface_center + right * half_width - up * half_height
    c := surface_center + right * half_width + up * half_height
    d := surface_center - right * half_width + up * half_height
    points := [6]third_person.Vec3{a, b, c, a, c, d}
    uvs := [6][2]f32{{0, 1}, {1, 1}, {1, 0}, {0, 1}, {1, 0}, {0, 0}}
    vertices: [6]World_Vertex
    encoded_room := interior_room
    if interior_room > .5 {
        variant := max(f32(math.floor(f64(interior_room))) - 1, 0)
        depth := clamp(interior_room - f32(math.floor(f64(interior_room))), f32(.35), f32(.95))
        aspect := clamp(width / max(height, f32(.001)), f32(.25), f32(4))
        depth_code := u32(math.round(f64((depth - .35) / .60 * 63)))
        aspect_code := u32(math.round(f64((aspect - .25) / 3.75 * 63)))
        payload := depth_code * 64 + aspect_code
        encoded_room = 1 + variant + (f32(payload) + .5) / 4096
    }
    for point, index in points {
        vertices[index] = world_vertex(point, color)
        vertices[index].kind = .Glass
        vertices[index].normal = {normal.x, normal.y, normal.z}
        vertices[index].material = {interior_light, encoded_room}
        vertices[index].uv = uvs[index]
    }
    append(&world_renderer.vertices, ..vertices[:])
}

world_architecture_window_room :: proc(
    structure: terrain.Structure,
    face: architecture.Face,
    row, column: int,
) -> f32 {
    key := structure.seed ~ u32(row * 0x45d9f3b) ~ u32(column * 0x119de1f3) ~ u32(face) * u32(0x9e3779b9)
    variant := f32((key >> 5) % 6)
    identity := architecture.architecture_resolve_legacy_identity(structure)
    switch identity.archetype {
    case .Dwelling, .Townhouse, .Farmstead:
        variant = 0 // Dwelling
    case .Shop_House, .Mixed_Use_Dwelling:
        variant = row == 0 ? 1 : 0 // Shop below, dwelling above
    case .Market_Hall:
        variant = 1 // Shop
    case .Workshop:
        variant = 2 // Workshop
    case .Barn_Granary, .Mill, .Fishery, .Storehouse:
        variant = 3 // Storehouse
    case .Campanile,
         .Palace_Loggia,
         .Church,
         .Monastery,
         .Fortress_Gate,
         .Harbor_Office,
         .Cycladic_Bell,
         .Post_Office,
         .Lighthouse:
        variant = 4 // Civic
    case .Clinic:
        variant = 5 // Clinic
    case .Legacy:
    // Legacy structures retain deterministic variety until their product
    // identity is resolved by settlement generation.
    }
    depth := f32(.52) + f32((key >> 13) & 255) / 255 * .38
    // The integer selects a procedural room family. world_glass_panel packs
    // depth and pane aspect into the fractional payload; zero remains flat glass.
    return 1 + variant + depth
}

world_architecture_window_plan :: proc(
    structure: terrain.Structure,
    width, height: f32,
    face: architecture.Face,
    row, column: int,
) -> facade_windows.Plan {
    identity := architecture.architecture_resolve_legacy_identity(structure)
    region: facade_windows.Region = identity.region == .Aegean ? .Aegean : .Adriatic
    config := facade_windows.defaults(region)
    key := structure.seed ~ u32(row * 0x45d9f3b) ~ u32(column * 0x119de1f3) ~ u32(face) * u32(0x9e3779b9)
    // Vary the fitted assembly rather than the authored wall opening. The
    // masonry layout therefore retains its clearance guarantees while nearby
    // windows acquire the restrained irregularity of renovated façades.
    building_width_scale := .92 + f32((structure.seed >> 4) & 15) / 15 * .07
    row_height_scale := .93 + f32((structure.seed ~ u32(row * 0x27d4eb2d)) & 15) / 15 * .06
    window_width_scale := building_width_scale * (.97 + f32((key >> 18) & 7) / 7 * .03)
    window_height_scale := row_height_scale * (.98 + f32((key >> 23) & 7) / 7 * .02)
    config.width = width * window_width_scale
    config.height = height * window_height_scale
    style := key % 7
    if region == .Aegean {
        config.shutter_style = style < 5 ? .Solid : .Louvered
        config.surround = .Whitewashed_Reveal
    } else {
        config.shutter_style = style < 3 ? .Louvered : (style < 5 ? .Solid : .Persiana)
        config.surround = style == 6 ? .Molded_Stone : .Dressed_Stone
    }
    state := (key >> 7) % 10
    if state == 0 {
        config.shutter_state = .Closed
        config.shutter_angle = 0
    } else if state < 3 {
        config.shutter_state = .Ajar
        config.shutter_angle = .42 + f32((key >> 12) & 31) / 31 * .28
    } else {
        config.shutter_state = .Open
        config.shutter_angle = 1.22 + f32((key >> 12) & 31) / 31 * .32
    }
    config.pane_columns = width > 1.18 ? 2 : 1
    config.pane_rows = height > 1.70 ? 3 : 2
    return facade_windows.generate(key, config)
}

world_architecture_window_shutter_leaf :: proc(
    plan: ^facade_windows.Plan,
    center: third_person.Vec3,
    rotation, side: f32,
    timber, iron: canvas2d.Color,
) {
    angle := plan.shutter_angle
    local_x := side * plan.width * .5 - side * math.cos(angle) * plan.shutter_width * .5
    local_z := .10 + math.sin(angle) * plan.shutter_width * .5
    x, z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
    yaw := rotation + side * angle
    lower_ratio := plan.lower_panel_ratio
    upper_height := plan.height * (1 - lower_ratio)
    upper_y := center.y + plan.height * .5 - upper_height * .5
    world_box_rotated({x, upper_y, z}, {plan.shutter_width, upper_height, plan.shutter_thickness}, yaw, timber)

    if plan.shutter_style != .Solid {
        usable_height := upper_height - .22
        count := max(3, int(f32(plan.louver_count) * (1 - lower_ratio)))
        for index in 0 ..< count {
            y := upper_y - usable_height * .5 + (f32(index) + .5) * usable_height / f32(count)
            slat_x, slat_z := world_rotate_xz(x, z, 0, .045, yaw)
            world_box_rotated({slat_x, y, slat_z}, {plan.shutter_width * .78, .035, .035}, yaw, iron)
        }
    } else {
        detail_x, detail_z := world_rotate_xz(x, z, 0, .045, yaw)
        world_box_rotated({detail_x, upper_y, detail_z}, {.045, upper_height * .82, .035}, yaw, iron)
        world_box_rotated({detail_x, upper_y, detail_z}, {plan.shutter_width * .82, .045, .035}, yaw, iron)
    }

    if plan.shutter_style == .Persiana {
        lower_height := plan.height * lower_ratio
        lower_y := center.y - plan.height * .5 + lower_height * .5
        kick_x, kick_z := world_rotate_xz(x, z, 0, lower_height * .23, yaw)
        world_box_rotated(
            {kick_x, lower_y, kick_z},
            {plan.shutter_width, lower_height, plan.shutter_thickness},
            yaw,
            timber,
        )
    }
}

world_architecture_generated_window :: proc(
    structure: terrain.Structure,
    center: third_person.Vec3,
    rotation, width, height: f32,
    face: architecture.Face,
    row, column: int,
    glass, surround, timber, iron: canvas2d.Color,
    interior_light: f32,
    shutters: bool = true,
) {
    plan := world_architecture_window_plan(structure, width, height, face, row, column)
    world_glass_panel(
        center,
        plan.width,
        plan.height,
        rotation,
        glass,
        interior_light,
        world_architecture_window_room(structure, face, row, column),
    )
    frame := plan.surround_width
    frame_depth := plan.surround_depth
    offsets := [4][3]f32 {
        {-plan.width * .5 - frame * .5, 0, frame},
        {plan.width * .5 + frame * .5, 0, frame},
        {0, plan.height * .5 + frame * .5, plan.width},
        {0, -plan.height * .5 - plan.sill_height * .5, plan.width + frame * 2.2},
    }
    for item, index in offsets {
        x, z := world_rotate_xz(center.x, center.z, item[0], index == 3 ? plan.sill_projection * .5 : .05, rotation)
        size :=
            index < 2 ? third_person.Vec3{frame, plan.height + frame * 2, frame_depth} : (index == 2 ? third_person.Vec3{item[2], frame, frame_depth} : third_person.Vec3{item[2], plan.sill_height, frame_depth + plan.sill_projection})
        world_box_rotated({x, center.y + item[1], z}, size, rotation, surround)
    }
    for pane_column in 1 ..< plan.pane_columns {
        local_x := -plan.width * .5 + f32(pane_column) * plan.width / f32(plan.pane_columns)
        x, z := world_rotate_xz(center.x, center.z, local_x, .075, rotation)
        world_box_rotated({x, center.y, z}, {.035, plan.height, .035}, rotation, iron)
    }
    for pane_row in 1 ..< plan.pane_rows {
        y := center.y - plan.height * .5 + f32(pane_row) * plan.height / f32(plan.pane_rows)
        x, z := world_rotate_xz(center.x, center.z, 0, .075, rotation)
        world_box_rotated({x, y, z}, {plan.width, .035, .035}, rotation, iron)
    }
    if shutters {
        // At building scale a short louver rhythm carries the material read
        // without multiplying each settlement window into dozens of boxes.
        plan.louver_count = min(plan.louver_count, 6)
        world_architecture_window_shutter_leaf(&plan, center, rotation, -1, timber, iron)
        world_architecture_window_shutter_leaf(&plan, center, rotation, 1, timber, iron)
    }
}

world_architecture_window_interior :: proc(
    structure: terrain.Structure,
    face: architecture.Face,
    row, column: int,
    storefront: bool = false,
) -> (
    canvas2d.Color,
    f32,
) {
    key := structure.seed ~ u32(row * 0x45d9f3b) ~ u32(column * 0x119de1f3) ~ u32(face) * u32(0x9e3779b9)
    occupied := key % 7 < 3
    if face != .Front do occupied = key % 7 < 2
    if storefront do occupied = true
    if !occupied do return {50, 76, 82, 255}, 0

    switch (key >> 8) % 3 {
    case 0:
        return {255, 184, 88, 255}, 1
    case 1:
        return {255, 207, 126, 255}, .92
    case:
        return {236, 164, 76, 255}, .84
    }
}

// Draw a terrain-following rectangular surface, discarding shoreline cells
// instead of letting a single rigid road or path slab continue over the ocean.
world_land_surface_rotated :: proc(
    editor: ^Editor,
    center_x, center_z, width, length, rotation, lift: f32,
    color: canvas2d.Color,
) {
    if editor == nil || width <= 0 || length <= 0 do return
    columns := max(1, int(math.ceil(f64(width / 2))))
    rows := max(1, int(math.ceil(f64(length / 2))))
    land_threshold := editor.project.sea_level + .04
    cosine, sine := math.cos(rotation), math.sin(rotation)
    samples_per_row := columns + 1
    resize(&world_renderer.land_surface_samples, samples_per_row * 2)
    previous := world_renderer.land_surface_samples[:samples_per_row]
    current := world_renderer.land_surface_samples[samples_per_row:]

    local_z0 := -length * .5
    for column in 0 ..= columns {
        local_x := -width * .5 + width * f32(column) / f32(columns)
        previous[column] = world_land_surface_sample(editor, center_x, center_z, local_x, local_z0, cosine, sine)
    }
    for row in 0 ..< rows {
        local_z1 := -length * .5 + length * f32(row + 1) / f32(rows)
        for column in 0 ..= columns {
            local_x := -width * .5 + width * f32(column) / f32(columns)
            current[column] = world_land_surface_sample(editor, center_x, center_z, local_x, local_z1, cosine, sine)
        }
        for column in 0 ..< columns {
            p00 := previous[column]
            p10 := previous[column + 1]
            p11 := current[column + 1]
            p01 := current[column]
            if p00.height <= land_threshold ||
               p10.height <= land_threshold ||
               p11.height <= land_threshold ||
               p01.height <= land_threshold {
                continue
            }
            world_quad(
                {p00.x, p00.height + lift, p00.z},
                {p01.x, p01.height + lift, p01.z},
                {p11.x, p11.height + lift, p11.z},
                {p10.x, p10.height + lift, p10.z},
                color,
            )
        }
        previous, current = current, previous
    }
}

world_settlement_material_land_surface_rotated :: proc(
    editor: ^Editor,
    center_x, center_z, width, length, rotation, lift: f32,
    material: Settlement_Material,
) {
    if editor == nil || width <= 0 || length <= 0 do return
    columns := max(1, int(math.ceil(f64(width / 2))))
    rows := max(1, int(math.ceil(f64(length / 2))))
    land_threshold := editor.project.sea_level + .04
    cosine, sine := math.cos(rotation), math.sin(rotation)
    for row in 0 ..< rows {
        z0 := -length * .5 + length * f32(row) / f32(rows)
        z1 := -length * .5 + length * f32(row + 1) / f32(rows)
        for column in 0 ..< columns {
            x0 := -width * .5 + width * f32(column) / f32(columns)
            x1 := -width * .5 + width * f32(column + 1) / f32(columns)
            p00 := world_land_surface_sample(editor, center_x, center_z, x0, z0, cosine, sine)
            p01 := world_land_surface_sample(editor, center_x, center_z, x0, z1, cosine, sine)
            p11 := world_land_surface_sample(editor, center_x, center_z, x1, z1, cosine, sine)
            p10 := world_land_surface_sample(editor, center_x, center_z, x1, z0, cosine, sine)
            if min(min(p00.height, p01.height), min(p11.height, p10.height)) <= land_threshold do continue
            world_settlement_material_quad(
                {p00.x, p00.height + lift, p00.z},
                {p01.x, p01.height + lift, p01.z},
                {p11.x, p11.height + lift, p11.z},
                {p10.x, p10.height + lift, p10.z},
                material,
                x1 - x0,
                z1 - z0,
                {x0 + width * .5, z0 + length * .5},
            )
        }
    }
}

world_airport_land_surface_rotated :: world_settlement_material_land_surface_rotated

// A short terrain-following trapezoid connects a broad pedestrian/service
// route to the road edge without the blunt rectangular mouth of the main run.
world_land_surface_tapered :: proc(
    editor: ^Editor,
    endpoint_x, endpoint_z, inward_x, inward_z: f32,
    run, inner_width, outer_width, lift: f32,
    color: canvas2d.Color,
) {
    if editor == nil || run <= .01 || inner_width <= 0 || outer_width <= 0 do return
    direction_length := f32(math.sqrt(f64(inward_x * inward_x + inward_z * inward_z)))
    if direction_length <= .001 do return
    tangent_x, tangent_z := inward_x / direction_length, inward_z / direction_length
    normal_x, normal_z := -tangent_z, tangent_x
    inner_x, inner_z := endpoint_x + tangent_x * run, endpoint_z + tangent_z * run
    outer_half, inner_half := outer_width * .5, inner_width * .5
    points := [4][2]f32 {
        {endpoint_x + normal_x * outer_half, endpoint_z + normal_z * outer_half},
        {inner_x + normal_x * inner_half, inner_z + normal_z * inner_half},
        {inner_x - normal_x * inner_half, inner_z - normal_z * inner_half},
        {endpoint_x - normal_x * outer_half, endpoint_z - normal_z * outer_half},
    }
    heights: [4]f32
    land_threshold := editor.project.sea_level + .04
    for point, index in points {
        heights[index] = terrain.sample_surface_height(&editor.project, 0, point[0], point[1])
        if heights[index] <= land_threshold do return
    }
    world_quad(
        {points[0][0], heights[0] + lift, points[0][1]},
        {points[1][0], heights[1] + lift, points[1][1]},
        {points[2][0], heights[2] + lift, points[2][1]},
        {points[3][0], heights[3] + lift, points[3][1]},
        color,
    )
}

world_land_surface_disc :: proc(editor: ^Editor, center_x, center_z, radius, lift: f32, color: canvas2d.Color) {
    if editor == nil || radius <= 0 do return
    segment_count := max(12, int(math.ceil(f64(radius * 10))))
    center_height := terrain.sample_surface_height(&editor.project, 0, center_x, center_z)
    land_threshold := editor.project.sea_level + .04
    if center_height <= land_threshold do return
    for segment in 0 ..< segment_count {
        first_angle := math.TAU * f32(segment) / f32(segment_count)
        second_angle := math.TAU * f32(segment + 1) / f32(segment_count)
        first_x, first_z := center_x + math.cos(first_angle) * radius, center_z + math.sin(first_angle) * radius
        second_x, second_z := center_x + math.cos(second_angle) * radius, center_z + math.sin(second_angle) * radius
        first_height := terrain.sample_surface_height(&editor.project, 0, first_x, first_z)
        second_height := terrain.sample_surface_height(&editor.project, 0, second_x, second_z)
        if first_height <= land_threshold || second_height <= land_threshold do continue
        world_triangle(
            {center_x, center_height + lift, center_z},
            {first_x, first_height + lift, first_z},
            {second_x, second_height + lift, second_z},
            color,
        )
    }
}

world_architecture_face_color :: proc(
    base: canvas2d.Color,
    normal_x, normal_z: f32,
    top: bool = false,
) -> canvas2d.Color {
    // A restrained baked key keeps the plain-color architecture readable
    // without fighting the authored stucco palette or the dynamic sky.
    shade := top ? f32(1.015) : clamp(.955 + normal_x * -.035 + normal_z * -.025, f32(.90), f32(1.01))
    return {
        r = u8(clamp(f32(base.r) * shade, 0, 255)),
        g = u8(clamp(f32(base.g) * shade, 0, 255)),
        b = u8(clamp(f32(base.b) * shade, 0, 255)),
        a = base.a,
    }
}

@(no_instrumentation)
world_architecture_quad :: #force_inline proc(a, b, c, d: third_person.Vec3, color: canvas2d.Color, material: f32) {
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    vertices := [6]World_Vertex {
        world_vertex(a, color),
        world_vertex(b, color),
        world_vertex(c, color),
        world_vertex(a, color),
        world_vertex(c, color),
        world_vertex(d, color),
    }
    for &vertex in vertices {
        vertex.kind = .Architecture
        vertex.normal = {normal.x, normal.y, normal.z}
        vertex.material = {material, 0}
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_architecture_triangle :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color: canvas2d.Color,
    material: f32 = 0,
) {
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    vertices := [3]World_Vertex{world_vertex(a, color), world_vertex(b, color), world_vertex(c, color)}
    for &vertex in vertices {
        vertex.kind = .Architecture
        vertex.normal = {normal.x, normal.y, normal.z}
        vertex.material = {material, 0}
    }
    append(&world_renderer.vertices, ..vertices[:])
}

world_architecture_box_rotated :: proc(
    center: third_person.Vec3,
    size: third_person.Vec3,
    rotation: f32,
    color: canvas2d.Color,
    material: f32 = 0,
) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    cosine, sine := f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))
    back := world_architecture_face_color(color, sine, -cosine)
    front := world_architecture_face_color(color, -sine, cosine)
    left := world_architecture_face_color(color, -cosine, -sine)
    right := world_architecture_face_color(color, cosine, sine)
    top := world_architecture_face_color(color, 0, 0, true)
    bottom := world_architecture_face_color(color, 0, 0)
    // Preserve the same outward CCW winding as world_box_rotated.
    world_architecture_quad(p[0], p[3], p[2], p[1], back, material)
    world_architecture_quad(p[4], p[5], p[6], p[7], front, material)
    world_architecture_quad(p[0], p[4], p[7], p[3], left, material)
    world_architecture_quad(p[1], p[2], p[6], p[5], right, material)
    world_architecture_quad(p[3], p[7], p[6], p[2], top, material)
    world_architecture_quad(p[0], p[1], p[5], p[4], bottom, material)
}

world_tapered_box_rotated :: proc(
    center: third_person.Vec3,
    height, bottom_width, bottom_depth, top_width, top_depth, rotation: f32,
    color: canvas2d.Color,
) {
    half_height := height * .5
    local := [8][3]f32 {
        {-bottom_width * .5, -half_height, -bottom_depth * .5},
        {bottom_width * .5, -half_height, -bottom_depth * .5},
        {top_width * .5, half_height, -top_depth * .5},
        {-top_width * .5, half_height, -top_depth * .5},
        {-bottom_width * .5, -half_height, bottom_depth * .5},
        {bottom_width * .5, -half_height, bottom_depth * .5},
        {top_width * .5, half_height, top_depth * .5},
        {-top_width * .5, half_height, top_depth * .5},
    }
    p: [8]third_person.Vec3
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

world_vertical_prism :: proc(
    center: third_person.Vec3,
    radius_x, radius_z, height, rotation: f32,
    color: canvas2d.Color,
) {
    SEGMENTS :: 8
    bottom, top: [SEGMENTS]third_person.Vec3
    half_height := height * .5
    for segment in 0 ..< SEGMENTS {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
        local_x := math.cos(angle) * radius_x
        local_z := math.sin(angle) * radius_z
        world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
        bottom[segment] = {world_x, center.y - half_height, world_z}
        top[segment] = {world_x, center.y + half_height, world_z}
    }
    bottom_center := third_person.Vec3{center.x, center.y - half_height, center.z}
    top_center := third_person.Vec3{center.x, center.y + half_height, center.z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_quad(bottom[segment], top[segment], top[next], bottom[next], color)
        world_triangle(bottom_center, bottom[segment], bottom[next], color)
        world_triangle(top_center, top[next], top[segment], color)
    }
}
