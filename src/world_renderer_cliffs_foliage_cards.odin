package main
import "core:math"

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

world_cliff_formation :: proc(structure: terrain.Structure, lod: Structure_LOD = .Near) {
    segments := lod == .Near ? 6 : lod == .Medium ? 4 : 2
    color := canvas2d.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    front_bottom: [7]third_person.Vec3
    front_top: [7]third_person.Vec3
    back_top: [7]third_person.Vec3
    back_bottom: [7]third_person.Vec3
    for segment in 0 ..= segments {
        fraction := f32(segment) / f32(segments)
        local_x := (fraction - .5) * structure.width
        top_jitter := f32(math.sin(f64(f32(structure.seed) * .001 + f32(segment) * 1.73))) * .055
        top_y := structure.base_y + structure.height * (.84 + top_jitter)
        front_x, front_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            -structure.depth * .5,
            structure.rotation,
        )
        back_x, back_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            structure.depth * .08,
            structure.rotation,
        )
        foot_x, foot_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            structure.depth * .5,
            structure.rotation,
        )
        front_bottom[segment] = {front_x, structure.base_y, front_z}
        front_top[segment] = {front_x, top_y, front_z}
        back_top[segment] = {back_x, top_y, back_z}
        back_bottom[segment] = {foot_x, structure.base_y + structure.height * .14, foot_z}
    }
    for segment in 0 ..< segments {
        front_face := formation_face_color(color, -math.PI * .5, 0)
        top_face := formation_face_color(color, 0, 1)
        back_face := formation_face_color(color, math.PI * .5, 0)
        world_quad(
            front_bottom[segment],
            front_bottom[segment + 1],
            front_top[segment + 1],
            front_top[segment],
            front_face,
        )
        world_quad(front_top[segment], front_top[segment + 1], back_top[segment + 1], back_top[segment], top_face)
        world_quad(back_top[segment], back_top[segment + 1], back_bottom[segment + 1], back_bottom[segment], back_face)
    }
    world_quad(front_bottom[0], back_bottom[0], back_top[0], front_top[0], formation_face_color(color, -math.PI, 0))
    world_quad(
        front_bottom[segments],
        front_top[segments],
        back_top[segments],
        back_bottom[segments],
        formation_face_color(color, 0, 0),
    )
}

world_limestone_color :: proc(kind: terrain.Formation_Kind) -> [4]u8 {
    if kind == .Cliff do return {193, 191, 178, 255}
    return {215, 211, 193, 255}
}

world_foliage_card :: proc(
    center: third_person.Vec3,
    width, height: f32,
    tile: int,
    color: canvas2d.Color,
    mirror: bool,
    flip_vertical := false,
) {
    editor := world_renderer.editor
    if editor == nil do return
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    right := third_person.Vec3{camera.right.x * width * .5, camera.right.y * width * .5, camera.right.z * width * .5}
    up := third_person.Vec3{camera.up.x * height * .5, camera.up.y * height * .5, camera.up.z * height * .5}
    p0 := third_person.Vec3{center.x - right.x - up.x, center.y - right.y - up.y, center.z - right.z - up.z}
    p1 := third_person.Vec3{center.x + right.x - up.x, center.y + right.y - up.y, center.z + right.z - up.z}
    p2 := third_person.Vec3{center.x + right.x + up.x, center.y + right.y + up.y, center.z + right.z + up.z}
    p3 := third_person.Vec3{center.x - right.x + up.x, center.y - right.y + up.y, center.z - right.z + up.z}

    atlas_tile := ((tile % 16) + 16) % 16
    column, row := atlas_tile % 4, atlas_tile / 4
    // A two-pixel inset prevents linear filtering from borrowing color from
    // the neighboring cell in the 1254px atlas.
    inset := f32(2.0 / 1254.0)
    u0 := f32(column) * .25 + inset
    v0 := f32(row) * .25 + inset
    u1 := f32(column + 1) * .25 - inset
    v1 := f32(row + 1) * .25 - inset
    if mirror {
        u0, u1 = u1, u0
    }
    if flip_vertical {
        v0, v1 = v1, v0
    }
    tint := world_color(color)
    append(
        &world_renderer.foliage_vertices,
        Foliage_Vertex{{p0.x, p0.y, p0.z}, {u0, v1}, tint, 0},
        Foliage_Vertex{{p1.x, p1.y, p1.z}, {u1, v1}, tint, 0},
        Foliage_Vertex{{p2.x, p2.y, p2.z}, {u1, v0}, tint, 0},
        Foliage_Vertex{{p0.x, p0.y, p0.z}, {u0, v1}, tint, 0},
        Foliage_Vertex{{p2.x, p2.y, p2.z}, {u1, v0}, tint, 0},
        Foliage_Vertex{{p3.x, p3.y, p3.z}, {u0, v0}, tint, 0},
    )
}

world_bougainvillea_card :: proc(
    center: third_person.Vec3,
    width, height: f32,
    tile: int,
    mirror: bool,
    roll: f32 = 0,
    value: f32 = 1,
    young_growth: bool = false,
    yaw_bias: f32 = 0,
) {
    editor := world_renderer.editor
    if editor == nil do return
    if climbing_leaf_card_capture != nil {
        append(climbing_leaf_card_capture, Bougainvillea_Card_Descriptor {
            center       = center,
            width        = width,
            height       = height,
            tile         = tile,
            mirror       = mirror,
            roll         = roll,
            value        = value,
            young_growth = young_growth,
            yaw_bias     = yaw_bias,
        })
    }
    append(&world_renderer.bougainvillea_instances, Bougainvillea_Instance {
        center   = {center.x, center.y, center.z},
        size     = {width, height},
        tile     = u32(((tile % 16) + 16) % 16),
        params   = {mirror ? f32(1) : f32(0), roll, value, young_growth ? f32(1) : f32(0)},
        yaw_bias = yaw_bias,
    })
    return
}

// Retained temporarily as a parity reference while the GPU descriptor path is
// validated against captures. It is no longer called by the renderer.
world_bougainvillea_card_legacy_cpu :: proc(
    center: third_person.Vec3,
    width, height: f32,
    tile: int,
    mirror: bool,
    roll: f32 = 0,
    value: f32 = 1,
    young_growth: bool = false,
    yaw_bias: f32 = 0,
) {
    editor := world_renderer.editor
    if editor == nil do return
    atlas_tile := ((tile % 16) + 16) % 16
    // Normalized painted branch origins within each atlas cell. Upright
    // clumps root near bottom-center; lateral sprays root at the appropriate
    // lower corner. Aligning these rather than each card's geometric center
    // keeps the generated foliage visibly attached to its procedural branch.
    anchors := [16][2]f32 {
        {.50, .90},
        {.12, .88},
        {.50, .91},
        {.08, .88},
        {.50, .90},
        {.12, .88},
        {.50, .91},
        {.08, .88},
        {.50, .90},
        {.10, .87},
        {.50, .91},
        {.08, .88},
        {.50, .90},
        {.10, .88},
        {.50, .92},
        {.08, .88},
    }
    anchor_x, anchor_y := anchors[atlas_tile][0], anchors[atlas_tile][1]
    texture_anchor_x := anchor_x
    if mirror do anchor_x = 1 - anchor_x
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    // Constrained cylindrical billboarding keeps the painted stem origin
    // mostly vertical as the camera pitches. A small camera-up contribution
    // prevents severe foreshortening in low-angle architectural views without
    // letting the clump lean freely like a HUD sprite.
    horizontal_right_length := f32(math.sqrt(f64(camera.right.x * camera.right.x + camera.right.z * camera.right.z)))
    if horizontal_right_length < .001 do horizontal_right_length = 1
    right_scale := width * .5 / horizontal_right_length
    right := third_person.Vec3{camera.right.x * right_scale, 0, camera.right.z * right_scale}
    if math.abs(yaw_bias) > .0001 {
        // Secondary crown layers can sit on a slightly different vertical
        // plane while remaining upright. This restrained yaw produces real
        // parallax instead of a stack of parallel camera-facing cutouts.
        yaw_cosine, yaw_sine := f32(math.cos(f64(yaw_bias))), f32(math.sin(f64(yaw_bias)))
        right = {right.x * yaw_cosine + right.z * yaw_sine, 0, -right.x * yaw_sine + right.z * yaw_cosine}
    }
    constrained_up := linalg.normalize0(
        third_person.Vec3{camera.up.x * .28, .72 + camera.up.y * .28, camera.up.z * .28},
    )
    up := third_person.Vec3 {
        constrained_up.x * height * .5,
        constrained_up.y * height * .5,
        constrained_up.z * height * .5,
    }
    if math.abs(roll) > .0001 {
        roll_cosine, roll_sine := f32(math.cos(f64(roll))), f32(math.sin(f64(roll)))
        unit_right := third_person.Vec3{right.x / (width * .5), right.y / (width * .5), right.z / (width * .5)}
        unit_up := third_person.Vec3{up.x / (height * .5), up.y / (height * .5), up.z / (height * .5)}
        right = {
            (unit_right.x * roll_cosine + unit_up.x * roll_sine) * width * .5,
            (unit_right.y * roll_cosine + unit_up.y * roll_sine) * width * .5,
            (unit_right.z * roll_cosine + unit_up.z * roll_sine) * width * .5,
        }
        up = {
            (-unit_right.x * roll_sine + unit_up.x * roll_cosine) * height * .5,
            (-unit_right.y * roll_sine + unit_up.y * roll_cosine) * height * .5,
            (-unit_right.z * roll_sine + unit_up.z * roll_cosine) * height * .5,
        }
    }
    anchored_center := third_person.Vec3 {
        center.x + right.x * (1 - anchor_x * 2) + up.x * (anchor_y * 2 - 1),
        center.y + right.y * (1 - anchor_x * 2) + up.y * (anchor_y * 2 - 1),
        center.z + right.z * (1 - anchor_x * 2) + up.z * (anchor_y * 2 - 1),
    }
    p0 := third_person.Vec3 {
        anchored_center.x - right.x - up.x,
        anchored_center.y - right.y - up.y,
        anchored_center.z - right.z - up.z,
    }
    p1 := third_person.Vec3 {
        anchored_center.x + right.x - up.x,
        anchored_center.y + right.y - up.y,
        anchored_center.z + right.z - up.z,
    }
    p2 := third_person.Vec3 {
        anchored_center.x + right.x + up.x,
        anchored_center.y + right.y + up.y,
        anchored_center.z + right.z + up.z,
    }
    p3 := third_person.Vec3 {
        anchored_center.x - right.x + up.x,
        anchored_center.y - right.y + up.y,
        anchored_center.z - right.z + up.z,
    }

    column, row := atlas_tile % 4, atlas_tile / 4
    inset := f32(2.0 / 1254.0)
    u0 := f32(column) * .25 + inset
    v0 := f32(row) * .25 + inset
    u1 := f32(column + 1) * .25 - inset
    v1 := f32(row + 1) * .25 - inset
    if mirror do u0, u1 = u1, u0
    anchor_u := u0 + (u1 - u0) * anchor_x
    anchor_v := v0 + (v1 - v0) * anchor_y
    // Alpha above one is an internal shader marker: use the native atlas
    // colors instead of treating this texture as a luminance tint mask.
    // Native cards use RGB as compact metadata: layer value, texture-space
    // anchor X, and texture-space anchor Y. This keeps shader wind weighting
    // synchronized with the single authoritative atlas anchor table above.
    // Alpha is an internal native-card marker rather than visible opacity.
    // Three marks bronze-flushed new growth; two marks established foliage.
    native_color := [4]f32{value, texture_anchor_x, anchor_y, young_growth ? f32(3) : f32(2)}
    positions: [3][3]third_person.Vec3
    positions[0] = {p3, linalg.lerp(p3, p2, anchor_x), p2}
    positions[1] = {linalg.lerp(p3, p0, anchor_y), center, linalg.lerp(p2, p1, anchor_y)}
    positions[2] = {p0, linalg.lerp(p0, p1, anchor_x), p1}
    card_u := [3]f32{u0, anchor_u, u1}
    card_v := [3]f32{v0, anchor_v, v1}
    for card_row in 0 ..< 2 {
        for card_column in 0 ..< 2 {
            top_left := positions[card_row][card_column]
            top_right := positions[card_row][card_column + 1]
            bottom_left := positions[card_row + 1][card_column]
            bottom_right := positions[card_row + 1][card_column + 1]
            left_u, right_u := card_u[card_column], card_u[card_column + 1]
            top_v, bottom_v := card_v[card_row], card_v[card_row + 1]
            append(
                &world_renderer.bougainvillea_vertices,
                Foliage_Vertex{{bottom_left.x, bottom_left.y, bottom_left.z}, {left_u, bottom_v}, native_color, 0},
                Foliage_Vertex{{bottom_right.x, bottom_right.y, bottom_right.z}, {right_u, bottom_v}, native_color, 0},
                Foliage_Vertex{{top_right.x, top_right.y, top_right.z}, {right_u, top_v}, native_color, 0},
                Foliage_Vertex{{bottom_left.x, bottom_left.y, bottom_left.z}, {left_u, bottom_v}, native_color, 0},
                Foliage_Vertex{{top_right.x, top_right.y, top_right.z}, {right_u, top_v}, native_color, 0},
                Foliage_Vertex{{top_left.x, top_left.y, top_left.z}, {left_u, top_v}, native_color, 0},
            )
        }
    }
}

world_window_flower_bunch_billboard :: proc(
    structure: terrain.Structure,
    local_x, root_y, local_z, window_width: f32,
    row, column: int,
) {
    seed := structure.seed ~ u32(row + 1) * 0x9e3779b9 ~ u32(column + 1) * 0x85ebca6b
    root_x, root_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
    palette := architecture.bougainvillea_palette(seed)
    flower_tile := architecture.bougainvillea_flower_tile_base(palette)
    // Even atlas columns are upright, bottom-anchored clumps: a natural fit
    // for a window box where the stems must visibly emerge from the planter.
    variation := int((seed >> 8) & 1) * 2
    width := window_width + .32
    height := row == 0 ? f32(.58) : f32(.92)
    roll := (f32(int((seed >> 12) % 7)) - 3) * .025
    world_bougainvillea_card(
        {root_x, root_y, root_z},
        width,
        height,
        flower_tile + variation,
        seed & 1 != 0,
        roll,
        .96,
    )
}

@(no_instrumentation)
world_grass_card :: proc(center: third_person.Vec3, width, height: f32, tile: int, color: canvas2d.Color) {
    append(&world_renderer.grass_instances, Grass_Instance {
        center = {center.x, center.y, center.z},
        size   = {width, height},
        tile   = u32(((tile % 16) + 16) % 16),
        color  = world_color(color),
    })
}

world_wildflower_card :: proc(center: third_person.Vec3, width, height: f32, tile: int) {
    append(
        &world_renderer.wildflower_instances,
        Grass_Instance {
            center = {center.x, center.y, center.z},
            size   = {width, height},
            tile   = u32(((tile % 16) + 16) % 16),
            // Alpha above one marks a native-color wildflower atlas card.
            color  = {1, 1, 1, 2},
        },
    )
}

world_marsh_card :: proc(center: third_person.Vec3, width, height: f32, tile: int) {
    palette := [4]canvas2d.Color{{78, 120, 85, 245}, {104, 132, 72, 245}, {139, 126, 70, 245}, {91, 118, 94, 245}}
    normalized_tile := ((tile % 16) + 16) % 16
    append(
        &world_renderer.marsh_instances,
        Grass_Instance {
            center = {center.x, center.y, center.z},
            size   = {width, height},
            tile   = u32(normalized_tile),
            // Use the atlas for silhouette/detail while keeping tidal plants
            // inside a coherent blue-green, olive, and straw palette.
            color  = world_color(palette[normalized_tile % len(palette)]),
        },
    )
}

world_wildflower_lab :: proc() {
    // A self-contained meadow makes atlas, scale, density, and wind regressions
    // visible without inheriting any gameplay-world state.
    world_box({0, -.12, 0}, {32, .24, 24}, {62, 113, 72, 255})
    SPACING :: f32(.52)
    for grid_z in -20 ..= 20 {
        for grid_x in -26 ..= 26 {
            seed := grid_x * 73856093 + grid_z * 19349663
            x := f32(grid_x) * SPACING + (wind_streak_hash(seed, 1) - .5) * SPACING * .72
            z := f32(grid_z) * SPACING + (wind_streak_hash(seed, 2) - .5) * SPACING * .72
            distance := f32(math.sqrt(f64(x * x + z * z)))
            edge := clamp((11.5 - distance) / 2.5, 0, 1)
            if wind_streak_hash(seed, 3) > edge do continue
            height := .48 + wind_streak_hash(seed, 4) * .55
            grass_color := color_lerp(
                canvas2d.Color{48, 113, 72, 255},
                canvas2d.Color{91, 137, 69, 255},
                wind_streak_hash(seed, 5),
            )
            world_grass_card(
                {x, height * .5, z},
                height * (.58 + wind_streak_hash(seed, 6) * .34),
                height,
                abs(seed) % 16,
                grass_color,
            )
            flower_chance := .16 + .34 * clamp(1 - distance / 12, 0, 1)
            if wind_streak_hash(seed, 7) < flower_chance {
                flower_height := .34 + wind_streak_hash(seed, 8) * .34
                world_wildflower_card(
                    {x, flower_height * .5 + .12, z},
                    .22 + wind_streak_hash(seed, 9) * .18,
                    flower_height,
                    abs(seed / 11) % 16,
                )
            }
        }
    }
}

@(no_instrumentation)
world_foliage_vertex_color :: #force_inline proc(ring, variation: int) -> canvas2d.Color {
    // Six broad Adriatic vegetation families: cypress, laurel, sunlit olive,
    // myrtle, silver olive, and warm Mediterranean scrub. Keeping each family
    // coherent from root pocket to crown gives the world postcard-scale color
    // regions without turning individual trees into multicolored noise.
    FOLIAGE_PALETTE_COUNT :: 6
    palette := ((variation % FOLIAGE_PALETTE_COUNT) + FOLIAGE_PALETTE_COUNT) % FOLIAGE_PALETTE_COUNT
    switch ring {
    case 0:
        colors := [6]canvas2d.Color {
            {31, 65, 55, 255},
            {47, 76, 42, 255},
            {62, 76, 39, 255},
            {40, 70, 55, 255},
            {61, 75, 57, 255},
            {52, 74, 42, 255},
        }
        return colors[palette]
    case 1:
        // A deliberately cool, low-value shoulder remains visible in the
        // narrow gaps between overlapping lobes, acting as painted contact
        // shadow without another texture lookup or render pass.
        colors := [6]canvas2d.Color {
            {43, 84, 68, 255},
            {62, 96, 48, 255},
            {81, 99, 48, 255},
            {52, 91, 69, 255},
            {78, 94, 69, 255},
            {70, 94, 49, 255},
        }
        return colors[palette]
    case 2:
        // Upper crown rings stay within one restrained body-color family.
        // Broad value grouping belongs to the continuous foliage shader;
        // large per-ring jumps expose the triangulated construction as bright
        // ribbons when a tree is viewed near eye level.
        colors := [6]canvas2d.Color {
            {61, 111, 88, 255},
            {90, 129, 62, 255},
            {129, 145, 65, 255},
            {75, 119, 88, 255},
            {116, 128, 91, 255},
            {103, 130, 65, 255},
        }
        return colors[palette]
    case 3:
        colors := [6]canvas2d.Color {
            {66, 119, 94, 255},
            {96, 139, 67, 255},
            {143, 158, 71, 255},
            {82, 128, 96, 255},
            {126, 138, 99, 255},
            {112, 141, 70, 255},
        }
        return colors[palette]
    case 4:
        colors := [6]canvas2d.Color {
            {75, 130, 99, 255},
            {103, 150, 70, 255},
            {158, 171, 74, 255},
            {92, 139, 102, 255},
            {139, 150, 105, 255},
            {121, 153, 73, 255},
        }
        return colors[palette]
    case 5:
        colors := [6]canvas2d.Color {
            {83, 140, 104, 255},
            {110, 160, 72, 255},
            {172, 182, 75, 255},
            {101, 149, 108, 255},
            {151, 160, 111, 255},
            {131, 163, 76, 255},
        }
        return colors[palette]
    case 6:
        colors := [6]canvas2d.Color {
            {92, 151, 107, 255},
            {119, 171, 75, 255},
            {187, 195, 78, 255},
            {111, 161, 111, 255},
            {165, 174, 116, 255},
            {143, 176, 78, 255},
        }
        return colors[palette]
    }
    return {78, 112, 53, 255}
}

@(no_instrumentation)
world_foliage_clump_color :: #force_inline proc(ring, variation: int, clump: f32) -> canvas2d.Color {
    // Extend the ring palette with a clump-aligned temperature and value shift.
    // Troughs between the rounded bunches sink into a cooler, lower-value
    // pocket -- soft painted ambient occlusion in the crevices -- while the
    // crests lift toward a warmer sunlit accent. Both are derived from the
    // ring's own body color so every species and palette family stays
    // harmonized, and the shift stays gentle so the grouped painted planes
    // never resolve into bright ribbons that expose the triangulation.
    base := world_foliage_vertex_color(ring, variation)
    if clump < 0 {
        // Deeper occlusion on the lower shoulders, where overlapping boughs
        // trap shade; the upper crown plane keeps only a faint recess.
        pocket_amount := clamp(-clump, 0, 1) * (.42 - f32(ring) * .035)
        pocket := canvas2d.Color{u8(f32(base.r) * .70), u8(f32(base.g) * .81), u8(f32(base.b) * .90), base.a}
        return color_lerp(base, pocket, clamp(pocket_amount, 0, 1))
    }
    crest_amount := clamp(clump, 0, 1) * .22
    crest := canvas2d.Color {
        u8(min(f32(base.r) * 1.15, 255.0)),
        u8(min(f32(base.g) * 1.08, 255.0)),
        u8(f32(base.b) * .93),
        base.a,
    }
    return color_lerp(base, crest, crest_amount)
}
