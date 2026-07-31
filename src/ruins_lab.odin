package main

import atmosphere "../packages/atmosphere"
import roads "../packages/roads"
import ruins "../packages/ruins"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

RUINS_LAB_DEFAULT_SEED :: u32(0x5255494e)

ruins_lab_seed := RUINS_LAB_DEFAULT_SEED
ruins_lab_mode := ruins.Mode.Complex
ruins_lab_culture := ruins.Culture.Aegean
ruins_lab_terrain := ruins.Terrain_Profile.Flat
ruins_lab_preservation := ruins.Preservation.Weathered
ruins_lab_pottery_density := ruins.Pottery_Density.Typical
ruins_lab_complex_scale := ruins.Complex_Scale.Standard
ruins_lab_plan: ruins.Plan
ruins_lab_show_props := true
ruins_lab_show_paths := true

RUINS_LAB_MATERIAL_METALLIC :: f32(0)
RUINS_LAB_MATERIAL_ROUGHNESS :: f32(.88)

ruins_lab_shaded_box_rotated :: proc(
    center: third_person.Vec3,
    size: third_person.Vec3,
    rotation: f32,
    color: canvas2d.Color,
) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
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
    points: [8]third_person.Vec3
    for index in 0 ..< len(points) {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        points[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad_lit(
        points[0],
        points[3],
        points[2],
        points[1],
        color,
        RUINS_LAB_MATERIAL_METALLIC,
        RUINS_LAB_MATERIAL_ROUGHNESS,
    )
    world_quad_lit(
        points[4],
        points[5],
        points[6],
        points[7],
        color,
        RUINS_LAB_MATERIAL_METALLIC,
        RUINS_LAB_MATERIAL_ROUGHNESS,
    )
    world_quad_lit(
        points[0],
        points[4],
        points[7],
        points[3],
        color,
        RUINS_LAB_MATERIAL_METALLIC,
        RUINS_LAB_MATERIAL_ROUGHNESS,
    )
    world_quad_lit(
        points[1],
        points[2],
        points[6],
        points[5],
        color,
        RUINS_LAB_MATERIAL_METALLIC,
        RUINS_LAB_MATERIAL_ROUGHNESS,
    )
    world_quad_lit(
        points[3],
        points[7],
        points[6],
        points[2],
        color,
        RUINS_LAB_MATERIAL_METALLIC,
        RUINS_LAB_MATERIAL_ROUGHNESS,
    )
    world_quad_lit(
        points[0],
        points[1],
        points[5],
        points[4],
        color,
        RUINS_LAB_MATERIAL_METALLIC,
        RUINS_LAB_MATERIAL_ROUGHNESS,
    )
}

ruins_lab_shaded_box :: proc(center, size: third_person.Vec3, color: canvas2d.Color) {
    ruins_lab_shaded_box_rotated(center, size, 0, color)
}

ruins_lab_shaded_box_between :: proc(a, b, forward: third_person.Vec3, width, depth: f32, color: canvas2d.Color) {
    delta := b - a
    length := linalg.length(delta)
    if length <= .0001 do return
    axis_y := delta / length
    axis_z := linalg.normalize0(forward)
    axis_x := linalg.cross(axis_y, axis_z)
    axis_x_length := linalg.length(axis_x)
    if axis_x_length <= .0001 {
        axis_x = linalg.cross(axis_y, third_person.Vec3{0, 1, 0})
        axis_x_length = linalg.length(axis_x)
    }
    axis_x = axis_x_length > .0001 ? axis_x / axis_x_length : third_person.Vec3{1, 0, 0}
    center := (a + b) * .5
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
    points: [8]third_person.Vec3
    for index in 0 ..< len(points) {
        x := signs[index][0] * width * .5
        y := signs[index][1] * length * .5
        z := signs[index][2] * depth * .5
        points[index] = center + axis_x * x + axis_y * y + axis_z * z
    }
    world_quad_lit(points[0], points[3], points[2], points[1], color, 0, RUINS_LAB_MATERIAL_ROUGHNESS)
    world_quad_lit(points[4], points[5], points[6], points[7], color, 0, RUINS_LAB_MATERIAL_ROUGHNESS)
    world_quad_lit(points[0], points[4], points[7], points[3], color, 0, RUINS_LAB_MATERIAL_ROUGHNESS)
    world_quad_lit(points[1], points[2], points[6], points[5], color, 0, RUINS_LAB_MATERIAL_ROUGHNESS)
    world_quad_lit(points[3], points[7], points[6], points[2], color, 0, RUINS_LAB_MATERIAL_ROUGHNESS)
    world_quad_lit(points[0], points[1], points[5], points[4], color, 0, RUINS_LAB_MATERIAL_ROUGHNESS)
}

ruins_lab_shaded_vertical_prism :: proc(
    center: third_person.Vec3,
    radius_x, radius_z, height, rotation: f32,
    color: canvas2d.Color,
) {
    SEGMENTS :: 8
    bottom, top: [SEGMENTS]third_person.Vec3
    half_height := height * .5
    for segment in 0 ..< SEGMENTS {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
        world_x, world_z := world_rotate_xz(
            center.x,
            center.z,
            math.cos(angle) * radius_x,
            math.sin(angle) * radius_z,
            rotation,
        )
        bottom[segment] = {world_x, center.y - half_height, world_z}
        top[segment] = {world_x, center.y + half_height, world_z}
    }
    bottom_center := third_person.Vec3{center.x, center.y - half_height, center.z}
    top_center := third_person.Vec3{center.x, center.y + half_height, center.z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_quad_lit(bottom[segment], top[segment], top[next], bottom[next], color, 0, RUINS_LAB_MATERIAL_ROUGHNESS)
        world_triangle_smooth_lit(
            bottom_center,
            bottom[segment],
            bottom[next],
            {0, -1, 0},
            {0, -1, 0},
            {0, -1, 0},
            color,
            color,
            color,
            RUINS_LAB_MATERIAL_ROUGHNESS,
        )
        world_triangle_smooth_lit(
            top_center,
            top[next],
            top[segment],
            {0, 1, 0},
            {0, 1, 0},
            {0, 1, 0},
            color,
            color,
            color,
            RUINS_LAB_MATERIAL_ROUGHNESS,
        )
    }
}

Ruins_Lab_View :: enum u8 {
    Overview,
    Anchor,
    Feature,
    Gateway,
    Phase,
    Storage,
}

ruins_lab_view := Ruins_Lab_View.Overview

ruins_lab_regenerate :: proc() {
    ruins_lab_plan = ruins.generate_for_site(
        ruins_lab_culture,
        ruins_lab_mode,
        ruins_lab_seed,
        ruins.default_site(ruins_lab_terrain),
        ruins_lab_preservation,
        ruins_lab_pottery_density,
        ruins_lab_complex_scale,
    )
}

ruins_lab_camera :: proc(editor: ^Editor) {
    if ruins_lab_view == .Feature && ruins_lab_plan.feature_count > 0 {
        feature := ruins_lab_plan.features[0]
        focus := third_person.Vec3{feature.position.x, feature.base_y + .35, feature.position.z}
        editor.camera_pose = third_person.camera_look_at({focus.x + 9, focus.y + 7, focus.z + 11}, focus)
    } else if ruins_lab_view == .Gateway && ruins_lab_plan.has_gateway {
        gateway := ruins_lab_plan.gateway
        focus := third_person.Vec3{gateway.position.x, gateway.base_y + .55, gateway.position.z}
        editor.camera_pose = third_person.camera_look_at({focus.x + 10, focus.y + 6.5, focus.z + 9}, focus)
    } else if ruins_lab_view == .Anchor && ruins_lab_plan.building_count > 0 {
        building := ruins_lab_plan.buildings[0]
        focus := third_person.Vec3{building.center.x, building.base_y + 1.2, building.center.z}
        editor.camera_pose = third_person.camera_look_at({focus.x + 18, focus.y + 13, focus.z + 21}, focus)
    } else if ruins_lab_view == .Phase && ruins_lab_plan.building_count > 1 {
        phase_index := min(2, ruins_lab_plan.building_count - 1)
        for building, index in ruins_lab_plan.buildings[:ruins_lab_plan.building_count] {
            if building.occupation_phase == .Reoccupation {
                phase_index = index
                break
            }
        }
        building := ruins_lab_plan.buildings[phase_index]
        focus := third_person.Vec3{building.center.x, building.base_y + .75, building.center.z}
        editor.camera_pose = third_person.camera_look_at({focus.x + 13, focus.y + 10, focus.z + 15}, focus)
    } else if ruins_lab_view == .Storage && ruins_lab_plan.building_count > 0 {
        // Storage QA follows the culturally characteristic storage building.
        storage_index := 0
        wanted := ruins_lab_culture == .Minoan ? ruins.Building_Kind.Magazine : ruins.Building_Kind.Villa
        for building, index in ruins_lab_plan.buildings[:ruins_lab_plan.building_count] {
            if building.kind == wanted {
                storage_index = index
                break
            }
        }
        building := ruins_lab_plan.buildings[storage_index]
        focus := third_person.Vec3{building.center.x, building.base_y + .65, building.center.z}
        editor.camera_pose = third_person.camera_look_at({focus.x + 10, focus.y + 8, focus.z + 12}, focus)
    } else if ruins_lab_mode == .Complex {
        distance := ruins_lab_plan.extent * .76
        editor.camera_pose = third_person.camera_look_at({distance, distance * .86, distance * 1.15}, {0, 2, 0})
    } else {
        editor.camera_pose = third_person.camera_look_at({20, 14, 24}, {0, 2, 0})
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

ruins_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60 + 40)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    ruins_lab_mode =
        target == "single" || target == "ruin" || target == "roman-single" || target == "minoan-single" ? .Ruin : .Complex
    ruins_lab_culture = .Aegean
    if target == "roman" || target == "roman-single" || target == "roman-incline" || target == "roman-terraced" {
        ruins_lab_culture = .Roman
    }
    if target == "roman-detail" ||
       target == "roman-feature" ||
       target == "roman-gateway" ||
       target == "roman-preserved" ||
       target == "roman-collapsed" ||
       target == "roman-collapsed-detail" ||
       target == "roman-phase" ||
       target == "roman-storage" ||
       target == "roman-rich-storage" ||
       target == "roman-extensive" ||
       target == "roman-terraced-detail" {
        ruins_lab_culture = .Roman
    }
    if target == "minoan" || target == "minoan-single" || target == "minoan-incline" || target == "minoan-terraced" {
        ruins_lab_culture = .Minoan
    }
    if target == "minoan-detail" ||
       target == "minoan-feature" ||
       target == "minoan-gateway" ||
       target == "minoan-preserved" ||
       target == "minoan-collapsed" ||
       target == "minoan-collapsed-detail" ||
       target == "minoan-phase" ||
       target == "minoan-storage" ||
       target == "minoan-rich-storage" ||
       target == "minoan-extensive" ||
       target == "minoan-terraced-detail" {
        ruins_lab_culture = .Minoan
    }
    ruins_lab_terrain = .Flat
    if target == "incline" || target == "roman-incline" || target == "minoan-incline" do ruins_lab_terrain = .Incline
    if target == "terraced" ||
       target == "roman-terraced" ||
       target == "minoan-terraced" ||
       target == "roman-terraced-detail" ||
       target == "minoan-terraced-detail" {
        ruins_lab_terrain = .Terraced
    }
    ruins_lab_show_props = true
    ruins_lab_show_paths = true
    ruins_lab_complex_scale = .Standard
    if target == "extensive" || target == "roman-extensive" || target == "minoan-extensive" {
        ruins_lab_complex_scale = .Extensive
    }
    ruins_lab_pottery_density = .Typical
    if target == "rich-storage" || target == "roman-rich-storage" || target == "minoan-rich-storage" {
        ruins_lab_pottery_density = .Abundant
    }
    ruins_lab_preservation = .Weathered
    if target == "preserved" || target == "roman-preserved" || target == "minoan-preserved" {
        ruins_lab_preservation = .Preserved
    }
    if target == "collapsed" ||
       target == "roman-collapsed" ||
       target == "minoan-collapsed" ||
       target == "roman-collapsed-detail" ||
       target == "minoan-collapsed-detail" {
        ruins_lab_preservation = .Collapsed
    }
    ruins_lab_view = .Overview
    if target == "detail" ||
       target == "roman-detail" ||
       target == "minoan-detail" ||
       target == "roman-collapsed-detail" ||
       target == "minoan-collapsed-detail" ||
       target == "roman-terraced-detail" ||
       target == "minoan-terraced-detail" {
        ruins_lab_view = .Anchor
    }
    if target == "feature" || target == "roman-feature" || target == "minoan-feature" do ruins_lab_view = .Feature
    if target == "gateway" || target == "roman-gateway" || target == "minoan-gateway" do ruins_lab_view = .Gateway
    if target == "phase" || target == "roman-phase" || target == "minoan-phase" do ruins_lab_view = .Phase
    if target == "storage" ||
       target == "roman-storage" ||
       target == "minoan-storage" ||
       target == "rich-storage" ||
       target == "roman-rich-storage" ||
       target == "minoan-rich-storage" {
        ruins_lab_view = .Storage
    }
    ruins_lab_regenerate()
    ruins_lab_camera(editor)
    return true
}

ruins_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    changed := false
    if canvas2d.IsKeyPressed(.R) {
        ruins_lab_seed += 1
        changed = true
    }
    if canvas2d.IsKeyPressed(.ONE) {
        ruins_lab_mode = .Ruin
        changed = true
    }
    if canvas2d.IsKeyPressed(.TWO) {
        ruins_lab_mode = .Complex
        changed = true
    }
    if canvas2d.IsKeyPressed(.C) {
        ruins_lab_culture = ruins.Culture((int(ruins_lab_culture) + 1) % len(ruins.Culture))
        changed = true
    }
    if canvas2d.IsKeyPressed(.T) {
        ruins_lab_terrain = ruins.Terrain_Profile((int(ruins_lab_terrain) + 1) % len(ruins.Terrain_Profile))
        changed = true
    }
    if canvas2d.IsKeyPressed(.D) {
        ruins_lab_preservation = ruins.Preservation((int(ruins_lab_preservation) + 1) % len(ruins.Preservation))
        changed = true
    }
    if canvas2d.IsKeyPressed(.G) {
        ruins_lab_pottery_density = ruins.Pottery_Density(
            (int(ruins_lab_pottery_density) + 1) % len(ruins.Pottery_Density),
        )
        changed = true
    }
    if canvas2d.IsKeyPressed(.B) {
        ruins_lab_complex_scale = ruins.Complex_Scale((int(ruins_lab_complex_scale) + 1) % len(ruins.Complex_Scale))
        changed = true
    }
    if canvas2d.IsKeyPressed(.P) do ruins_lab_show_props = !ruins_lab_show_props
    if canvas2d.IsKeyPressed(.V) do ruins_lab_show_paths = !ruins_lab_show_paths
    if canvas2d.IsKeyPressed(.F) {
        ruins_lab_view = Ruins_Lab_View((int(ruins_lab_view) + 1) % len(Ruins_Lab_View))
        ruins_lab_camera(editor)
    }
    if changed {
        ruins_lab_regenerate()
        ruins_lab_camera(editor)
    }
}

ruins_lab_local :: proc(building: ruins.Building, x, z: f32) -> third_person.Vec3 {
    p := ruins.local_to_world(building, {x, z})
    return {p.x, building.base_y, p.z}
}

ruins_lab_masonry_segment :: proc(
    building: ruins.Building,
    horizontal: bool,
    local_x, local_z, length, height: f32,
    salt: u32,
) {
    course_target, block_target := f32(.42), f32(1.10)
    if building.culture == .Roman {
        course_target, block_target = .29, .72
    } else if building.culture == .Minoan {
        course_target, block_target = .50, 1.32
    }
    course_count := max(int(math.ceil(height / course_target)), 1)
    course_height := height / f32(course_count)
    for course in 0 ..< course_count {
        block_count := max(int(math.ceil(length / block_target)) + course % 2, 1)
        block_length := length / f32(block_count)
        for block in 0 ..< block_count {
            block_salt := salt ~ u32(course * 131 + block * 17)
            along := -length * .5 + block_length * (f32(block) + .5)
            jitter := ruins.random_range(building.seed ~ block_salt ~ 1, -.025, .025)
            x, z := local_x, local_z
            if horizontal {
                x += along
            } else {
                z += along
            }
            center := ruins_lab_local(building, x, z)
            center.y = building.base_y + .16 + course_height * (f32(course) + .5)
            size := third_person.Vec3{.46, course_height - .018, max(block_length - .035, f32(.18))}
            if horizontal {
                size = {max(block_length - .035, f32(.18)), course_height - .018, .46}
            }
            color := canvas2d.Color{190, 177, 143, 255}
            if building.culture == .Roman {
                color = {181, 164, 137, 255}
                if course % 4 == 1 do color = {167, 105, 76, 255}
            } else if building.culture == .Minoan {
                color = {188, 170, 134, 255}
            } else {
                color = {190, 177, 143, 255}
            }
            if jitter > .012 {
                color = building.culture == .Roman ? canvas2d.Color{194, 178, 150, 255} : canvas2d.Color{205, 191, 157, 255}
            } else if jitter < -.012 {
                color = building.culture == .Minoan ? canvas2d.Color{164, 146, 113, 255} : canvas2d.Color{169, 157, 128, 255}
            }
            if building.occupation_phase == .Expansion && ruins.hash(building.seed ~ block_salt ~ 0x5ea1) % 11 < 3 {
                color = {201, 188, 158, 255}
                if building.culture == .Minoan do color = {151, 132, 101, 255}
            } else if building.occupation_phase == .Reoccupation &&
               course < 2 &&
               ruins.hash(building.seed ~ block_salt ~ 0x7e05e) % 7 < 3 {
                // Later occupants commonly repair the foot of a failing wall
                // with whatever local stone and tile remain close at hand.
                color = {128, 119, 91, 255}
                if building.culture == .Roman do color = {151, 111, 84, 255}
            }
            ruins_lab_shaded_box_rotated(center, size, building.yaw, color)
        }
    }
}

ruins_lab_wall_finish :: proc(
    building: ruins.Building,
    horizontal: bool,
    local_x, local_z, segment_length, wall_height: f32,
    side_index, segment: int,
) {
    if !ruins.wall_finish_patch_survives(building, side_index, segment) do return
    available_height := wall_height - .24
    if available_height < .38 do return

    salt := u32(side_index * 0x4f1 + segment * 0x91d) ~ 0xf17e5
    patch_length := segment_length * ruins.random_range(building.seed ~ salt ~ 1, .56, .88)
    patch_height := min(
        available_height,
        ruins.random_range(building.seed ~ salt ~ 2, .48, 1.34) * (.70 + ruins.wall_finish_coverage(building) * .42),
    )
    along_offset := ruins.random_range(
        building.seed ~ salt ~ 3,
        -(segment_length - patch_length) * .34,
        (segment_length - patch_length) * .34,
    )
    x, z := local_x, local_z
    if horizontal {
        x += along_offset
        z += side_index == 0 ? f32(.239) : f32(-.239)
    } else {
        z += along_offset
        x += side_index == 1 ? f32(-.239) : f32(.239)
    }
    center := ruins_lab_local(building, x, z)
    center.y = building.base_y + .19 + patch_height * .5
    size := third_person.Vec3{.026, patch_height, patch_length}
    if horizontal do size = {patch_length, patch_height, .026}

    base_color := canvas2d.Color{218, 202, 169, 255}
    accent_color := canvas2d.Color{139, 63, 45, 255}
    if building.wall_finish == .Minoan_Painted_Plaster {
        base_color = {198, 174, 132, 255}
        palette := [3]canvas2d.Color{{150, 50, 39, 255}, {43, 92, 111, 255}, {199, 145, 70, 255}}
        accent_color = palette[int(ruins.hash(building.seed ~ salt ~ 4) % 3)]
    }
    ruins_lab_shaded_box_rotated(center, size, building.yaw, base_color)

    // A surviving dado or painted band makes the finish legible at the lab's
    // overview distance while remaining flush with the interior wall face.
    band_height := min(patch_height * .30, f32(.30))
    band := center
    band.y = building.base_y + .19 + band_height * .5
    band_size := size
    band_size.y = band_height
    if horizontal {
        band_size.z = .032
    } else {
        band_size.x = .032
    }
    ruins_lab_shaded_box_rotated(band, band_size, building.yaw, accent_color)
}

ruins_lab_wall_run :: proc(building: ruins.Building, horizontal: bool, fixed, length: f32, side_index: int) {
    cap_color := canvas2d.Color{218, 204, 168, 255}
    if building.culture == .Roman {
        cap_color = {205, 190, 164, 255}
    } else if building.culture == .Minoan {
        cap_color = {213, 193, 153, 255}
    }
    segments := max(int(math.ceil(length / 2.2)), 2)
    segment_length := length / f32(segments)
    for segment in 0 ..< segments {
        salt := u32(side_index * 31 + segment) * 0x9e3779b9
        damage_roll := ruins.random01(building.seed ~ salt)
        if damage_roll < building.damage * .24 do continue
        t := -length * .5 + segment_length * (f32(segment) + .5)
        // Keep a readable entrance wound in one selected wall.
        if side_index == building.entrance_side && math.abs(t) < segment_length * .7 do continue
        collapse_distance := f32(1000)
        if building.collapsed_sides & u8(1 << u32(side_index)) != 0 {
            collapse_distance = math.abs(t - building.collapse_centers[side_index])
            // The central missing stones are the source of the matching
            // tumbled-wall deposit immediately outside this run.
            if collapse_distance < segment_length * .72 do continue
        }
        height_factor := .34 + (1 - building.damage) * .58 + ruins.random01(building.seed ~ salt ~ 2) * .32
        if collapse_distance < segment_length * 1.65 {
            height_factor *= .28 + collapse_distance / (segment_length * 1.65) * .32
        }
        height := max(building.wall_height * height_factor, f32(.55))
        local_x, local_z := horizontal ? t : fixed, horizontal ? fixed : t
        center := ruins_lab_local(building, local_x, local_z)
        center.y = building.base_y + height * .5 + .16
        // Keep neighboring runs disjoint. Extending each run past its allotted
        // span makes the end blocks overlap on the same wall plane, so their
        // front and back faces compete in the depth buffer. The block inset in
        // ruins_lab_masonry_segment already supplies the visible mortar seam.
        ruins_lab_masonry_segment(building, horizontal, local_x, local_z, segment_length, height, salt)
        ruins_lab_wall_finish(building, horizontal, local_x, local_z, segment_length, height, side_index, segment)
        if damage_roll > .42 {
            cap := center
            cap.y = building.base_y + height + .20
            cap_size :=
                horizontal ? third_person.Vec3{segment_length + .14, .12, .58} : third_person.Vec3{.58, .12, segment_length + .14}
            ruins_lab_shaded_box_rotated(cap, cap_size, building.yaw, cap_color)
        }
    }
}

ruins_lab_column :: proc(building: ruins.Building, x, z: f32, index: int, painted: bool = false) {
    state := ruins.column_state(building, index, painted)
    height := building.wall_height * (.72 + ruins.random01(building.seed ~ u32(index) * 73) * .20)
    p := ruins_lab_local(building, x, z)
    shaft_color := painted ? canvas2d.Color{139, 48, 39, 255} : canvas2d.Color{207, 195, 163, 255}
    base_color := painted ? canvas2d.Color{76, 67, 55, 255} : canvas2d.Color{218, 205, 170, 255}
    capital_color := painted ? canvas2d.Color{58, 54, 45, 255} : canvas2d.Color{221, 207, 173, 255}
    ruins_lab_shaded_box_rotated(
        {p.x, p.y + .22, p.z},
        painted ? third_person.Vec3{.78, .20, .78} : third_person.Vec3{.92, .20, .92},
        building.yaw,
        base_color,
    )
    if state != .Standing {
        stump_height := height * ruins.random_range(building.seed ~ u32(index) * 79, .13, .28)
        ruins_lab_shaded_vertical_prism(
            {p.x, p.y + stump_height * .5 + .31, p.z},
            painted ? f32(.34) : f32(.33),
            painted ? f32(.39) : f32(.30),
            stump_height,
            building.yaw,
            shaft_color,
        )
        if state == .Stump do return

        fall_angle :=
            building.collapse_yaw - building.yaw + ruins.random_range(building.seed ~ u32(index) * 83, -.18, .18)
        drum_count := painted ? 2 : 3
        drum_length := min(height * .62 / f32(drum_count), f32(1.15))
        for drum in 0 ..< drum_count {
            offset := 1.0 + f32(drum) * (drum_length + .16)
            local_x := x + math.cos(fall_angle) * offset
            local_z := z + math.sin(fall_angle) * offset
            fallen := ruins_lab_local(building, local_x, local_z)
            fallen.y = building.base_y + .34 + f32(drum % 2) * .04
            ruins_lab_shaded_box_rotated(
                fallen,
                {drum_length, painted ? f32(.54) : f32(.58), painted ? f32(.54) : f32(.58)},
                building.yaw + fall_angle,
                shaft_color,
            )
        }
        return
    }
    if painted {
        height = building.wall_height * .74
        ruins_lab_shaded_vertical_prism(
            {p.x, p.y + height * .5 + .18, p.z},
            .32,
            .48,
            height,
            building.yaw,
            {139, 48, 39, 255},
        )
        ruins_lab_shaded_box_rotated({p.x, p.y + height + .22, p.z}, {.95, .20, .95}, building.yaw, capital_color)
        return
    }
    ruins_lab_shaded_vertical_prism({p.x, p.y + height * .5 + .18, p.z}, .34, .28, height, building.yaw, shaft_color)
    ruins_lab_shaded_box_rotated({p.x, p.y + height + .22, p.z}, {.78, .18, .78}, building.yaw, capital_color)
}

ruins_lab_columns :: proc(building: ruins.Building) {
    switch building.colonnade_layout {
    case .None:
        return
    case .Peristyle:
        depth_count := max(int(math.ceil(building.depth / 3)), 4)
        width_count := max(int(math.ceil(building.width / 3)), 3)
        index := 0
        for side in ([2]f32{-1, 1}) {
            for column in 0 ..< depth_count {
                z := -building.depth * .40 + building.depth * .80 * f32(column) / f32(depth_count - 1)
                ruins_lab_column(building, side * building.width * .38, z, index)
                index += 1
            }
        }
        for side in ([2]f32{-1, 1}) {
            for column in 1 ..< width_count - 1 {
                x := -building.width * .38 + building.width * .76 * f32(column) / f32(width_count - 1)
                ruins_lab_column(building, x, side * building.depth * .40, index)
                index += 1
            }
        }
    case .Frontage:
        for index in 0 ..< building.column_count {
            x := -building.width * .40 + building.width * .80 * f32(index) / f32(max(building.column_count - 1, 1))
            ruins_lab_column(building, x, -building.depth * .30, index)
        }
    case .Nave_Aisles:
        per_aisle := max(building.column_count / 2, 1)
        index := 0
        for side in ([2]f32{-1, 1}) {
            for column in 0 ..< per_aisle {
                z := -building.depth * .38 + building.depth * .76 * f32(column) / f32(max(per_aisle - 1, 1))
                ruins_lab_column(building, side * building.width * .22, z, index)
                index += 1
            }
        }
    case .Court:
        for index in 0 ..< building.column_count {
            x := -building.width * .34 + building.width * .68 * f32(index) / f32(max(building.column_count - 1, 1))
            ruins_lab_column(building, x, -building.depth * .18, index, true)
        }
    }
}

ruins_lab_portal_local :: proc(building: ruins.Building, tangent, y: f32) -> third_person.Vec3 {
    x, z := f32(0), f32(0)
    switch building.entrance_side {
    case 0:
        x, z = tangent, -building.depth * .5
    case 1:
        x, z = building.width * .5, tangent
    case 2:
        x, z = tangent, building.depth * .5
    case 3:
        x, z = -building.width * .5, tangent
    }
    p := ruins_lab_local(building, x, z)
    p.y = building.base_y + y
    return p
}

ruins_lab_portal_block :: proc(
    building: ruins.Building,
    tangent, y, tangent_width, height, depth: f32,
    color: canvas2d.Color,
) {
    size := third_person.Vec3{depth, height, tangent_width}
    if building.entrance_side == 0 || building.entrance_side == 2 {
        size = {tangent_width, height, depth}
    }
    ruins_lab_shaded_box_rotated(ruins_lab_portal_local(building, tangent, y), size, building.yaw, color)
}

ruins_lab_portal :: proc(building: ruins.Building) {
    stone := canvas2d.Color{218, 204, 168, 255}
    if building.culture == .Roman {
        stone = {201, 185, 157, 255}
    } else if building.culture == .Minoan {
        stone = {205, 183, 145, 255}
    }
    dark_stone := building.culture == .Minoan ? canvas2d.Color{76, 67, 55, 255} : canvas2d.Color{174, 160, 132, 255}
    jamb_height := building.culture == .Roman ? f32(1.65) : f32(1.95)
    jamb_width := building.culture == .Minoan ? f32(.48) : f32(.40)
    half_opening := building.culture == .Minoan ? f32(1.15) : f32(1.02)

    for side in ([2]f32{-1, 1}) {
        survival := ruins.random01(building.seed ~ u32(side > 0 ? 0xa17 : 0xb29))
        height := jamb_height
        if survival < building.damage * .42 {
            height *= ruins.random_range(building.seed ~ u32(side > 0 ? 0xc31 : 0xd43), .28, .58)
        }
        ruins_lab_portal_block(
            building,
            side * (half_opening + jamb_width * .5),
            .16 + height * .5,
            jamb_width,
            height,
            .62,
            building.culture == .Minoan && side > 0 ? canvas2d.Color{137, 55, 43, 255} : stone,
        )
    }

    if building.culture == .Roman {
        // Upright voussoirs form a stepped semicircular ruin silhouette while
        // retaining a full two-metre-clear opening beneath.
        for block in 0 ..< 9 {
            if ruins.random01(building.seed ~ u32(block * 0x71 + 0xe51)) < building.damage * .32 do continue
            angle := math.PI * f32(block) / 8
            tangent := math.cos(angle) * (half_opening + .18)
            y := .16 + jamb_height + math.sin(angle) * (half_opening + .18)
            ruins_lab_portal_block(building, tangent, y, .34, .34, .66, block % 2 == 0 ? stone : dark_stone)
        }
    } else {
        lintel_survives := ruins.random01(building.seed ~ 0x1a7e1) > building.damage * .48
        if lintel_survives {
            lintel_color := building.culture == .Minoan ? dark_stone : stone
            ruins_lab_portal_block(
                building,
                0,
                .16 + jamb_height + .20,
                half_opening * 2 + jamb_width * 2,
                .38,
                .70,
                lintel_color,
            )
        }
    }

    // Shallow approach stones clarify the entrance without occupying its
    // doorway clearance volume.
    for step in 0 ..< 2 {
        outside := .42 + f32(step) * .52
        p2 := ruins.entrance_position(building, outside)
        width, depth := f32(2.45), f32(.58)
        size := third_person.Vec3{depth, .12 + f32(1 - step) * .05, width}
        if building.entrance_side == 0 || building.entrance_side == 2 {
            size = {width, size.y, depth}
        }
        ruins_lab_shaded_box_rotated({p2.x, building.base_y + size.y * .5 + .02, p2.z}, size, building.yaw, dark_stone)
    }
}

ruins_lab_interior_run :: proc(
    building: ruins.Building,
    horizontal: bool,
    fixed, start, end, gap_center, gap_width, height: f32,
    salt: u32,
) {
    if ruins.random01(building.seed ~ salt) < building.damage * .18 do return
    actual_height := height * ruins.random_range(building.seed ~ salt ~ 1, .72, 1)
    left_end := min(gap_center - gap_width * .5, end)
    if left_end > start + .25 {
        length := left_end - start
        center := (start + left_end) * .5
        x, z := horizontal ? center : fixed, horizontal ? fixed : center
        ruins_lab_masonry_segment(building, horizontal, x, z, length, actual_height, salt ~ 2)
    }
    right_start := max(gap_center + gap_width * .5, start)
    if end > right_start + .25 {
        length := end - right_start
        center := (right_start + end) * .5
        x, z := horizontal ? center : fixed, horizontal ? fixed : center
        ruins_lab_masonry_segment(building, horizontal, x, z, length, actual_height, salt ~ 3)
    }
}

ruins_lab_interior :: proc(building: ruins.Building) {
    w, d := building.width, building.depth
    low := clamp(building.wall_height * .48, f32(.75), f32(2.15))
    switch building.interior_layout {
    case .None:
        return
    case .Cella:
        inner_w, inner_d := w * .52, d * .62
        ruins_lab_interior_run(building, true, -inner_d * .5, -inner_w * .5, inner_w * .5, 0, 1.6, low, 0xce11)
        ruins_lab_interior_run(building, true, inner_d * .5, -inner_w * .5, inner_w * .5, 0, 0, low, 0xce12)
        ruins_lab_interior_run(building, false, -inner_w * .5, -inner_d * .5, inner_d * .5, 0, 0, low, 0xce13)
        ruins_lab_interior_run(building, false, inner_w * .5, -inner_d * .5, inner_d * .5, 0, 0, low, 0xce14)
    case .Aisled_Hall:
        for side in ([2]f32{-1, 1}) {
            ruins_lab_interior_run(
                building,
                false,
                side * w * .23,
                -d * .40,
                d * .40,
                0,
                1.5,
                low * .58,
                side < 0 ? 0xa151 : 0xa152,
            )
        }
    case .Chambers:
        ruins_lab_interior_run(building, false, 0, -d * .43, d * .43, -d * .18, 1.55, low, 0xba71)
        ruins_lab_interior_run(building, true, -d * .12, -w * .44, w * .44, w * .20, 1.55, low, 0xba72)
        if building.room_count >= 6 {
            ruins_lab_interior_run(building, true, d * .22, -w * .44, w * .44, -w * .18, 1.45, low * .86, 0xba73)
        }
    case .Domestic_Rooms:
        ruins_lab_interior_run(building, false, 0, -d * .43, d * .43, d * .12, 1.45, low, 0xd041)
        ruins_lab_interior_run(building, true, 0, -w * .43, w * .43, -w * .16, 1.45, low, 0xd042)
        if building.room_count >= 5 {
            ruins_lab_interior_run(building, true, d * .24, -w * .43, w * .43, w * .20, 1.35, low * .82, 0xd043)
        }
    case .Courtyard:
        court_w, court_d := w * .38, d * .38
        ruins_lab_interior_run(building, true, -court_d * .5, -court_w * .5, court_w * .5, 0, 1.35, low, 0xc071)
        ruins_lab_interior_run(building, true, court_d * .5, -court_w * .5, court_w * .5, 0, 1.35, low, 0xc072)
        ruins_lab_interior_run(building, false, -court_w * .5, -court_d * .5, court_d * .5, 0, 1.35, low, 0xc073)
        ruins_lab_interior_run(building, false, court_w * .5, -court_d * .5, court_d * .5, 0, 1.35, low, 0xc074)
        if building.kind == .Palace {
            ruins_lab_interior_run(building, false, w * .32, -d * .42, d * .42, d * .16, 1.35, low * .9, 0xc075)
        }
    case .Magazines:
        for side in ([2]f32{-1, 1}) {
            ruins_lab_interior_run(
                building,
                false,
                side * w * .18,
                -d * .38,
                d * .38,
                -d * .20,
                1.25,
                low,
                side < 0 ? 0x6a61 : 0x6a62,
            )
        }
    }
}

ruins_lab_floor_finish :: proc(building: ruins.Building) {
    usable_width, usable_depth := building.width * .82, building.depth * .82
    panel_target := building.floor_finish == .Roman_Mosaic ? f32(1.55) : f32(2.15)
    columns := clamp(int(math.ceil(usable_width / panel_target)), 3, 10)
    rows := clamp(int(math.ceil(usable_depth / panel_target)), 3, 12)
    panel_width, panel_depth := usable_width / f32(columns), usable_depth / f32(rows)
    for row in 0 ..< rows {
        for column in 0 ..< columns {
            if !ruins.floor_finish_panel_survives(building, row, column) do continue
            salt := u32(row * 0x6d5 + column * 0xa91) ~ 0xf1002
            x := -usable_width * .5 + panel_width * (f32(column) + .5)
            z := -usable_depth * .5 + panel_depth * (f32(row) + .5)
            x += ruins.random_range(building.seed ~ salt ~ 1, -.08, .08)
            z += ruins.random_range(building.seed ~ salt ~ 2, -.08, .08)
            width_scale := ruins.random_range(building.seed ~ salt ~ 3, .78, .97)
            depth_scale := ruins.random_range(building.seed ~ salt ~ 4, .78, .97)
            p := ruins_lab_local(building, x, z)
            p.y = building.base_y + .185
            color := canvas2d.Color{174, 145, 91, 255}
            accent := canvas2d.Color{}
            has_accent := false
            if building.floor_finish == .Roman_Mosaic {
                palette := [2]canvas2d.Color{{220, 211, 188, 255}, {197, 182, 151, 255}}
                pattern := (row + column * 2 + int(ruins.hash(building.seed ~ 0x605a1c) % 3)) % 7
                color = palette[(row + column) % 2]
                if pattern == 0 || pattern == 3 {
                    has_accent = true
                    accent = pattern == 0 ? canvas2d.Color{73, 70, 62, 255} : canvas2d.Color{173, 96, 67, 255}
                }
            } else if building.floor_finish == .Minoan_Gypsum_Plaster {
                palette := [3]canvas2d.Color{{210, 195, 158, 255}, {188, 167, 128, 255}, {151, 76, 56, 255}}
                pattern := (row * 3 + column + int(ruins.hash(building.seed ~ 0x6a95) % 4)) % 9
                color = pattern == 0 ? palette[2] : palette[(row + column) % 2]
            } else if (row * 2 + column) % 5 == 0 {
                color = {151, 119, 75, 255}
            }
            ruins_lab_shaded_box_rotated(
                p,
                {panel_width * width_scale, .035, panel_depth * depth_scale},
                building.yaw,
                color,
            )
            if has_accent {
                motif := p
                motif.y += .021
                ruins_lab_shaded_box_rotated(
                    motif,
                    {panel_width * width_scale * .30, .018, panel_depth * depth_scale * .30},
                    building.yaw + math.PI * .25,
                    accent,
                )
            }
        }
    }
}

ruins_lab_occupation_traces :: proc(building: ruins.Building) {
    if building.occupation_phase == .Founding do return
    if building.occupation_phase == .Expansion {
        // A slightly offset, robbed-out footing preserves the outline of an
        // earlier room beneath the expanded building.
        offset_x := ruins.random_range(building.seed ~ 0xea71, -.65, .65)
        offset_z := ruins.random_range(building.seed ~ 0xea72, -.55, .55)
        width, depth := building.width * .58, building.depth * .54
        stone := canvas2d.Color{137, 128, 108, 255}
        if building.culture == .Minoan do stone = {119, 108, 85, 255}
        runs := [4]struct {
            x, z, width, depth: f32,
        } {
            {offset_x, offset_z - depth * .5, width, .24},
            {offset_x, offset_z + depth * .5, width, .24},
            {offset_x - width * .5, offset_z, .24, depth},
            {offset_x + width * .5, offset_z, .24, depth},
        }
        for run, index in runs {
            if ruins.random01(building.seed ~ u32(index) * 0x8a31 ~ 0xea73) < building.damage * .28 do continue
            p := ruins_lab_local(building, run.x, run.z)
            p.y = building.base_y + .235
            ruins_lab_shaded_box_rotated(p, {run.width, .10, run.depth}, building.yaw, stone)
        }
        return
    }

    // Reoccupation leaves a compact clay patch and stone hearth in a corner
    // opposite the formal entrance, never in the circulation throat.
    x_sign := ruins.hash(building.seed ~ 0x7e01) & 1 == 0 ? f32(-1) : f32(1)
    x, z := x_sign * building.width * .27, f32(0)
    if building.entrance_side == 0 do z = building.depth * .28
    if building.entrance_side == 2 do z = -building.depth * .28
    if building.entrance_side == 1 do x, z = -building.width * .28, x_sign * building.depth * .24
    if building.entrance_side == 3 do x, z = building.width * .28, x_sign * building.depth * .24
    patch := ruins_lab_local(building, x, z)
    patch.y = building.base_y + .222
    ruins_lab_shaded_box_rotated(patch, {2.25, .06, 1.75}, building.yaw, {142, 105, 70, 255})
    hearth_stone := building.culture == .Roman ? canvas2d.Color{151, 139, 120, 255} : canvas2d.Color{126, 113, 88, 255}
    for index in 0 ..< 6 {
        angle := f32(index) / 6 * math.PI * 2
        p := ruins_lab_local(building, x + math.cos(angle) * .56, z + math.sin(angle) * .56)
        p.y = building.base_y + .31
        ruins_lab_shaded_box_rotated(p, {.42, .18, .30}, building.yaw + angle, hearth_stone)
    }
    ash := ruins_lab_local(building, x, z)
    ash.y = building.base_y + .258
    ruins_lab_shaded_vertical_prism(ash, .40, .34, .035, building.yaw, {69, 66, 57, 255})
}

ruins_lab_signature_remain :: proc(building: ruins.Building) {
    switch building.signature_remain {
    case .None:
        return
    case .Basilica_Tribunal:
        // A raised tribunal occupies the rear of the nave, opposite the
        // ceremonial entrance, with a broken semicircular seat line.
        forward := ruins.Vec2{}
        if building.entrance_side == 0 do forward = {0, -1}
        if building.entrance_side == 1 do forward = {1, 0}
        if building.entrance_side == 2 do forward = {0, 1}
        if building.entrance_side == 3 do forward = {-1, 0}
        tangent := ruins.Vec2{-forward.z, forward.x}
        along_extent := math.abs(forward.x) > .5 ? building.width : building.depth
        across_extent := math.abs(tangent.x) > .5 ? building.width : building.depth
        center := ruins.Vec2{-forward.x * along_extent * .31, -forward.z * along_extent * .31}
        platform_width := min(across_extent * .54, f32(6.5))
        platform_depth := min(along_extent * .18, f32(3.0))
        for tier in 0 ..< 2 {
            local := ruins.Vec2{center.x + forward.x * f32(tier) * .22, center.z + forward.z * f32(tier) * .22}
            p := ruins_lab_local(building, local.x, local.z)
            p.y = building.base_y + .22 + f32(tier) * .12
            size := third_person.Vec3{platform_width - f32(tier) * .55, .20, platform_depth - f32(tier) * .30}
            if math.abs(forward.x) > .5 do size = {size.z, size.y, size.x}
            ruins_lab_shaded_box_rotated(
                p,
                size,
                building.yaw,
                tier == 0 ? canvas2d.Color{166, 153, 132, 255} : canvas2d.Color{195, 181, 154, 255},
            )
        }
        for seat in 0 ..< 7 {
            if ruins.random01(building.seed ~ u32(seat) * 0x771b) < building.damage * .25 do continue
            angle := -math.PI * .5 + math.PI * f32(seat) / 6
            local := ruins.Vec2 {
                center.x -
                forward.x * math.cos(angle) * platform_depth * .46 +
                tangent.x * math.sin(angle) * platform_width * .42,
                center.z -
                forward.z * math.cos(angle) * platform_depth * .46 +
                tangent.z * math.sin(angle) * platform_width * .42,
            }
            p := ruins_lab_local(building, local.x, local.z)
            p.y = building.base_y + .52
            ruins_lab_shaded_box_rotated(p, {.72, .34, .42}, building.yaw + angle, {187, 174, 149, 255})
        }
    case .Bath_Hypocaust:
        // Exposed pilae occupy a robbed service bay beside the cold room.
        for row in 0 ..< 3 {
            for column in 0 ..< 4 {
                index := row * 4 + column
                if ruins.random01(building.seed ~ u32(index) * 0x49a1) < building.damage * .22 do continue
                x := building.width * (.18 + f32(column) * .07)
                z := building.depth * (-.22 + f32(row) * .22)
                p := ruins_lab_local(building, x, z)
                p.y = building.base_y + .34
                ruins_lab_shaded_box_rotated(
                    p,
                    {.34, .38, .34},
                    building.yaw,
                    index % 3 == 0 ? canvas2d.Color{160, 79, 55, 255} : canvas2d.Color{184, 101, 70, 255},
                )
            }
        }
    case .Palace_Grand_Stair:
        stair_width := min(building.width * .30, f32(5.2))
        for step in 0 ..< 5 {
            depth := f32(.58)
            z := building.depth * .16 + f32(step) * depth
            p := ruins_lab_local(building, 0, z)
            height := .12 + f32(step) * .11
            p.y = building.base_y + .19 + height * .5
            ruins_lab_shaded_box_rotated(
                p,
                {stair_width - f32(step) * .16, height, depth + .06},
                building.yaw,
                step % 2 == 0 ? canvas2d.Color{181, 159, 120, 255} : canvas2d.Color{151, 132, 101, 255},
            )
        }
    case .Magazine_Pithos_Beds:
        for row in 0 ..< 2 {
            for bay in 0 ..< 4 {
                index := row * 4 + bay
                if ruins.random01(building.seed ~ u32(index) * 0x9175) < building.damage * .18 do continue
                x := (f32(row) - .5) * building.width * .34
                z := -building.depth * .30 + building.depth * .20 * f32(bay)
                p := ruins_lab_local(building, x, z)
                p.y = building.base_y + .245
                ruins_lab_shaded_vertical_prism(p, .48, .56, .16, building.yaw, {119, 105, 82, 255})
            }
        }
    }
}

ruins_lab_building :: proc(building: ruins.Building) {
    slab_color := canvas2d.Color{168, 158, 128, 255}
    if building.culture == .Roman {
        slab_color = {151, 137, 118, 255}
    } else if building.culture == .Minoan {
        slab_color = {143, 128, 101, 255}
    }
    slab := ruins_lab_local(building, 0, 0)
    foundation_height := building.base_y + .32
    course_target := f32(.80)
    if building.culture == .Roman do course_target = .66
    if building.culture == .Minoan do course_target = .96
    foundation_courses := max(int(math.ceil(foundation_height / course_target)), 1)
    course_height := foundation_height / f32(foundation_courses)
    foundation_color := canvas2d.Color{142, 132, 105, 255}
    if building.culture == .Roman do foundation_color = {148, 137, 119, 255}
    if building.culture == .Minoan do foundation_color = {132, 117, 91, 255}
    foundation_bottom := f32(-.24)
    for course in 0 ..< foundation_courses {
        // Lower retaining courses project slightly farther, producing a
        // stable stepped podium instead of a single terrain-extruded block.
        projection := f32(foundation_courses - course - 1) * .075
        center_y := foundation_bottom + course_height * (f32(course) + .5)
        color := foundation_color
        if course % 3 == 1 {
            color.r = u8(max(int(color.r) - 7, 0))
            color.g = u8(max(int(color.g) - 6, 0))
            color.b = u8(max(int(color.b) - 4, 0))
        }
        ruins_lab_shaded_box_rotated(
            {slab.x, center_y, slab.z},
            {building.width + 1.15 + projection * 2, course_height - .018, building.depth + 1.15 + projection * 2},
            building.yaw,
            color,
        )
    }
    ruins_lab_shaded_box_rotated(
        {slab.x, building.base_y + .08, slab.z},
        {building.width + .7, .16, building.depth + .7},
        building.yaw,
        slab_color,
    )
    ruins_lab_floor_finish(building)
    ruins_lab_occupation_traces(building)
    ruins_lab_wall_run(building, true, -building.depth * .5, building.width, 0)
    ruins_lab_wall_run(building, false, building.width * .5, building.depth, 1)
    ruins_lab_wall_run(building, true, building.depth * .5, building.width, 2)
    ruins_lab_wall_run(building, false, -building.width * .5, building.depth, 3)
    if building.kind == .Baths {
        // A sunken cold room makes Roman bath footprints recognizable.
        p := ruins_lab_local(building, 0, 0)
        ruins_lab_shaded_box_rotated(
            {p.x, building.base_y + .13, p.z},
            {building.width * .50, .10, building.depth * .42},
            building.yaw,
            {205, 188, 154, 255},
        )
        ruins_lab_shaded_box_rotated(
            {p.x, building.base_y + .20, p.z},
            {building.width * .42, .06, building.depth * .34},
            building.yaw,
            {72, 128, 137, 255},
        )
    } else if building.kind == .Villa || building.kind == .Palace {
        // Villas and Minoan palaces organize rooms around an open light court.
        p := ruins_lab_local(building, 0, 0)
        court_color := building.culture == .Minoan ? canvas2d.Color{177, 130, 86, 255} : canvas2d.Color{190, 178, 145, 255}
        ruins_lab_shaded_box_rotated(
            {p.x, building.base_y + .19, p.z},
            {building.width * .38, .08, building.depth * .38},
            building.yaw,
            court_color,
        )
    }
    ruins_lab_signature_remain(building)
    ruins_lab_interior(building)
    ruins_lab_portal(building)
    ruins_lab_columns(building)
}

ruins_lab_pot :: proc(prop: ruins.Prop, base_y: f32) {
    terracotta := canvas2d.Color{164, 82, 48, 255}
    height, radius := f32(.48), f32(.31)
    top_scale := f32(.72)
    if prop.kind == .Amphora do height, radius = .72, .25
    if prop.kind == .Pithos do height, radius, top_scale = 1.12, .46, .82
    if prop.kind == .Dolium do height, radius, top_scale = .86, .52, .76
    height *= prop.scale
    radius *= prop.scale
    ruins_lab_shaded_vertical_prism(
        {prop.position.x, base_y + height * .5 + .17, prop.position.z},
        radius,
        radius * top_scale,
        height,
        prop.yaw,
        terracotta,
    )
    ruins_lab_shaded_vertical_prism(
        {prop.position.x, base_y + height + .20, prop.position.z},
        radius * .68,
        radius * .68,
        .10,
        prop.yaw,
        {116, 59, 42, 255},
    )
    if prop.kind == .Pithos || prop.kind == .Dolium {
        band_color := prop.kind == .Pithos ? canvas2d.Color{112, 61, 43, 255} : canvas2d.Color{132, 70, 48, 255}
        for band in 0 ..< 2 {
            y := base_y + .17 + height * (.40 + f32(band) * .27)
            ruins_lab_shaded_vertical_prism(
                {prop.position.x, y, prop.position.z},
                radius * (1.02 - f32(band) * .08),
                radius * (1.02 - f32(band) * .08),
                .075 * prop.scale,
                prop.yaw,
                band_color,
            )
        }
    }
}

ruins_lab_pottery_sherds :: proc(prop: ruins.Prop, base_y: f32) {
    count := 5 + int(ruins.hash(prop.detail_seed) % 5)
    for index in 0 ..< count {
        salt := u32(index) * 0x9e3779b9
        angle := ruins.random_range(prop.detail_seed ~ salt ~ 1, 0, math.PI * 2)
        distance := math.sqrt(ruins.random01(prop.detail_seed ~ salt ~ 2)) * .48 * prop.scale
        x, z := math.cos(angle) * distance, math.sin(angle) * distance
        length := ruins.random_range(prop.detail_seed ~ salt ~ 3, .16, .36) * prop.scale
        width := ruins.random_range(prop.detail_seed ~ salt ~ 4, .08, .20) * prop.scale
        p := ruins_lab_prop_local(prop, base_y, x, .19 + f32(index % 3) * .012, z)
        color := index % 3 == 0 ? canvas2d.Color{188, 91, 55, 255} : canvas2d.Color{145, 70, 48, 255}
        ruins_lab_shaded_box_rotated(
            p,
            {length, .045, width},
            prop.yaw + angle + ruins.random_range(prop.detail_seed ~ salt ~ 5, -.35, .35),
            color,
        )
    }
    // One curved vessel base survives as a small low polygon amid the sherds.
    ruins_lab_shaded_vertical_prism(
        {prop.position.x, base_y + .22, prop.position.z},
        .17 * prop.scale,
        .12 * prop.scale,
        .08,
        prop.yaw,
        {161, 76, 49, 255},
    )
}

ruins_lab_prop_local :: proc(prop: ruins.Prop, base_y, x, y, z: f32) -> third_person.Vec3 {
    cosine, sine := math.cos(prop.yaw), math.sin(prop.yaw)
    return {prop.position.x + x * cosine - z * sine, base_y + y, prop.position.z + x * sine + z * cosine}
}

ruins_lab_tumbled_wall :: proc(prop: ruins.Prop, building: ruins.Building) {
    base_y := building.base_y
    stone := canvas2d.Color{174, 162, 133, 255}
    pale := canvas2d.Color{198, 185, 153, 255}
    count_base, length_base := 9, f32(3.8)
    width_low, width_high := f32(.48), f32(.92)
    if building.culture == .Roman {
        stone, pale = {157, 143, 126, 255}, {190, 174, 149, 255}
        count_base, length_base = 13, 4.5
        width_low, width_high = .34, .72
    } else if building.culture == .Minoan {
        stone, pale = {147, 130, 102, 255}, {184, 164, 126, 255}
        count_base, length_base = 7, 4.2
        width_low, width_high = .62, 1.18
    }
    count := count_base + int(ruins.hash(prop.detail_seed) % 6)
    length := length_base * prop.scale
    for index in 0 ..< count {
        salt := u32(index) * 0x9e3779b9
        x := ruins.random_range(prop.detail_seed ~ salt ~ 1, -length * .5, length * .5)
        spread := .72 + math.abs(x / max(length, .01)) * .45
        z := ruins.random_range(prop.detail_seed ~ salt ~ 2, -spread, spread) * prop.scale
        width := ruins.random_range(prop.detail_seed ~ salt ~ 3, width_low, width_high) * prop.scale
        height := ruins.random_range(prop.detail_seed ~ salt ~ 4, .22, .48) * prop.scale
        depth := ruins.random_range(prop.detail_seed ~ salt ~ 5, .38, .72) * prop.scale
        p := ruins_lab_prop_local(prop, base_y, x, height * .5 + .16, z)
        yaw := prop.yaw + ruins.random_range(prop.detail_seed ~ salt ~ 6, -.42, .42)
        color := index % 3 == 0 ? pale : stone
        if building.culture == .Roman && index % 5 == 0 {
            // Terracotta fragments make Roman wall falls distinguishable from
            // the larger dry-stone deposits used by Minoan construction.
            color = {174, 83, 54, 255}
            height *= .55
            depth *= 1.25
        }
        ruins_lab_shaded_box_rotated(p, {width, height, depth}, yaw, color)
    }
}

ruins_lab_masonry_pile :: proc(prop: ruins.Prop, building: ruins.Building) {
    base_y := building.base_y
    count := building.culture == .Roman ? 11 : (building.culture == .Minoan ? 7 : 8)
    for index in 0 ..< count {
        salt := u32(index) * 0x85ebca6b
        ring := math.sqrt(ruins.random01(prop.detail_seed ~ salt ~ 1))
        angle := ruins.random_range(prop.detail_seed ~ salt ~ 2, 0, math.PI * 2)
        x := math.cos(angle) * ring * 1.15 * prop.scale
        z := math.sin(angle) * ring * .82 * prop.scale
        size_low, size_high := f32(.34), f32(.72)
        if building.culture == .Roman do size_low, size_high = .28, .60
        if building.culture == .Minoan do size_low, size_high = .50, .92
        size := ruins.random_range(prop.detail_seed ~ salt ~ 3, size_low, size_high) * prop.scale
        p := ruins_lab_prop_local(prop, base_y, x, .16 + size * .28, z)
        stone := index % 3 == 0 ? canvas2d.Color{204, 190, 157, 255} : canvas2d.Color{166, 154, 126, 255}
        if building.culture == .Minoan {
            stone = index % 3 == 0 ? canvas2d.Color{185, 164, 126, 255} : canvas2d.Color{142, 126, 99, 255}
        }
        ruins_lab_shaded_box_rotated(
            p,
            {size, size * ruins.random_range(prop.detail_seed ~ salt ~ 4, .45, .85), size * .8},
            prop.yaw + angle,
            stone,
        )
    }
}

ruins_lab_roof_tile_pile :: proc(prop: ruins.Prop, base_y: f32) {
    for index in 0 ..< 10 {
        salt := u32(index) * 0xc2b2ae35
        row, column := index / 5, index % 5
        x := (f32(column) - 2) * .34 * prop.scale
        z := (f32(row) - .5) * .42 * prop.scale
        p := ruins_lab_prop_local(
            prop,
            base_y,
            x + ruins.random_range(prop.detail_seed ~ salt, -.08, .08),
            .19 + f32(row) * .07,
            z + ruins.random_range(prop.detail_seed ~ salt ~ 1, -.10, .10),
        )
        ruins_lab_shaded_box_rotated(
            p,
            {.48 * prop.scale, .09 * prop.scale, .72 * prop.scale},
            prop.yaw + ruins.random_range(prop.detail_seed ~ salt ~ 2, -.16, .16),
            index % 3 == 0 ? canvas2d.Color{153, 68, 45, 255} : canvas2d.Color{181, 86, 54, 255},
        )
    }
}

ruins_lab_fallen_timber :: proc(prop: ruins.Prop, base_y: f32) {
    beam_count := 2 + int(ruins.hash(prop.detail_seed) % 2)
    for index in 0 ..< beam_count {
        salt := u32(index) * 0x9e3779b9
        x := ruins.random_range(prop.detail_seed ~ salt ~ 1, -.25, .25)
        z := (f32(index) - f32(beam_count - 1) * .5) * .34 * prop.scale
        p := ruins_lab_prop_local(prop, base_y, x, .24 + f32(index) * .055, z)
        length := ruins.random_range(prop.detail_seed ~ salt ~ 2, 3.1, 4.25) * prop.scale
        color := index == 0 ? canvas2d.Color{75, 58, 39, 255} : canvas2d.Color{97, 70, 43, 255}
        ruins_lab_shaded_box_rotated(
            p,
            {length, .22 * prop.scale, .25 * prop.scale},
            prop.yaw + ruins.random_range(prop.detail_seed ~ salt ~ 3, -.12, .12),
            color,
        )
    }
}

ruins_lab_mudbrick_fall :: proc(prop: ruins.Prop, base_y: f32) {
    count := 9 + int(ruins.hash(prop.detail_seed) % 5)
    for index in 0 ..< count {
        salt := u32(index) * 0x85ebca6b
        angle := ruins.random_range(prop.detail_seed ~ salt ~ 1, 0, math.PI * 2)
        radius := math.sqrt(ruins.random01(prop.detail_seed ~ salt ~ 2))
        x := math.cos(angle) * radius * 1.18 * prop.scale
        z := math.sin(angle) * radius * .82 * prop.scale
        width := ruins.random_range(prop.detail_seed ~ salt ~ 3, .38, .72) * prop.scale
        height := ruins.random_range(prop.detail_seed ~ salt ~ 4, .16, .34) * prop.scale
        depth := ruins.random_range(prop.detail_seed ~ salt ~ 5, .30, .58) * prop.scale
        p := ruins_lab_prop_local(prop, base_y, x, .16 + height * .5, z)
        color := index % 3 == 0 ? canvas2d.Color{164, 119, 76, 255} : canvas2d.Color{143, 101, 67, 255}
        ruins_lab_shaded_box_rotated(p, {width, height, depth}, prop.yaw + angle, color)
    }
}

ruins_lab_grass_tuft :: proc(prop: ruins.Prop, base_y: f32) {
    blade_count := 5 + int(ruins.hash(prop.detail_seed) % 4)
    for index in 0 ..< blade_count {
        salt := u32(index) * 0x9e3779b9
        angle := prop.yaw + ruins.random_range(prop.detail_seed ~ salt ~ 1, -1.25, 1.25)
        distance := ruins.random_range(prop.detail_seed ~ salt ~ 2, 0, .18) * prop.scale
        height := ruins.random_range(prop.detail_seed ~ salt ~ 3, .28, .62) * prop.scale
        center := third_person.Vec3 {
            prop.position.x + math.cos(angle) * distance,
            base_y + .16 + height * .5,
            prop.position.z + math.sin(angle) * distance,
        }
        color := index % 3 == 0 ? canvas2d.Color{116, 119, 62, 255} : canvas2d.Color{91, 105, 55, 255}
        ruins_lab_shaded_box_rotated(center, {.045, height, .09}, angle, color)
    }
}

ruins_lab_scrub :: proc(prop: ruins.Prop, base_y: f32) {
    height := ruins.random_range(prop.detail_seed ~ 1, .60, 1.02) * prop.scale
    ruins_lab_shaded_vertical_prism(
        {prop.position.x, base_y + .17 + height * .38, prop.position.z},
        .07 * prop.scale,
        .05 * prop.scale,
        height * .76,
        prop.yaw,
        {91, 76, 48, 255},
    )
    for index in 0 ..< 5 {
        salt := u32(index) * 0x85ebca6b
        angle := prop.yaw + f32(index) / 5 * math.PI * 2
        radius := ruins.random_range(prop.detail_seed ~ salt ~ 2, .18, .38) * prop.scale
        y := base_y + .17 + height * ruins.random_range(prop.detail_seed ~ salt ~ 3, .48, .88)
        color := index % 2 == 0 ? canvas2d.Color{86, 103, 57, 255} : canvas2d.Color{105, 116, 63, 255}
        ruins_lab_shaded_vertical_prism(
            {prop.position.x + math.cos(angle) * radius, y, prop.position.z + math.sin(angle) * radius},
            .22 * prop.scale,
            .17 * prop.scale,
            .24 * prop.scale,
            angle,
            color,
        )
    }
}

ruins_lab_prop :: proc(prop: ruins.Prop, building: ruins.Building) {
    base_y := building.base_y
    switch prop.kind {
    case .Pot, .Amphora, .Pithos, .Dolium:
        ruins_lab_pot(prop, base_y)
    case .Pottery_Sherds:
        ruins_lab_pottery_sherds(prop, base_y)
    case .Rubble:
        ruins_lab_shaded_box_rotated(
            {prop.position.x, base_y + .18 * prop.scale, prop.position.z},
            {.65 * prop.scale, .36 * prop.scale, .48 * prop.scale},
            prop.yaw,
            {172, 161, 132, 255},
        )
    case .Fallen_Column:
        ruins_lab_shaded_box_rotated(
            {prop.position.x, base_y + .38 * prop.scale, prop.position.z},
            {3.5 * prop.scale, .62 * prop.scale, .62 * prop.scale},
            prop.yaw,
            {199, 187, 157, 255},
        )
    case .Tumbled_Wall:
        ruins_lab_tumbled_wall(prop, building)
    case .Masonry_Pile:
        ruins_lab_masonry_pile(prop, building)
    case .Roof_Tile_Pile:
        ruins_lab_roof_tile_pile(prop, base_y)
    case .Fallen_Timber:
        ruins_lab_fallen_timber(prop, base_y)
    case .Mudbrick_Fall:
        ruins_lab_mudbrick_fall(prop, base_y)
    case .Grass_Tuft:
        ruins_lab_grass_tuft(prop, base_y)
    case .Scrub:
        ruins_lab_scrub(prop, base_y)
    }
}

ruins_lab_site_feature :: proc(feature: ruins.Site_Feature) {
    p := feature.position
    y := feature.base_y
    s := feature.scale
    switch feature.kind {
    case .Altar_Platform:
        ruins_lab_shaded_box_rotated({p.x, y + .12, p.z}, {3.1 * s, .24, 2.45 * s}, feature.yaw, {171, 158, 126, 255})
        ruins_lab_shaded_box_rotated({p.x, y + .31, p.z}, {2.35 * s, .18, 1.72 * s}, feature.yaw, {196, 181, 146, 255})
        ruins_lab_shaded_box_rotated({p.x, y + .52, p.z}, {1.18 * s, .42, .82 * s}, feature.yaw, {181, 166, 133, 255})
    case .Cistern:
        // Layered native prisms suggest a broken circular curb and surviving
        // water without requiring a mesh or texture asset.
        ruins_lab_shaded_vertical_prism(
            {p.x, y + .18, p.z},
            1.85 * s,
            1.85 * s,
            .36,
            feature.yaw,
            {151, 139, 119, 255},
        )
        ruins_lab_shaded_vertical_prism(
            {p.x, y + .39, p.z},
            1.43 * s,
            1.43 * s,
            .09,
            feature.yaw,
            {199, 186, 157, 255},
        )
        ruins_lab_shaded_vertical_prism({p.x, y + .45, p.z}, 1.12 * s, 1.12 * s, .07, feature.yaw, {69, 112, 119, 255})
        // A displaced curb stone keeps the remain from looking pristine.
        offset := ruins_lab_prop_local({position = p, yaw = feature.yaw}, y, 1.55 * s, .31, .25 * s)
        ruins_lab_shaded_box_rotated(offset, {.78 * s, .34, .48 * s}, feature.yaw + .28, {183, 169, 143, 255})
    case .Lustral_Basin:
        ruins_lab_shaded_box_rotated({p.x, y + .09, p.z}, {3.4 * s, .18, 2.8 * s}, feature.yaw, {142, 126, 98, 255})
        ruins_lab_shaded_box_rotated({p.x, y + .20, p.z}, {2.75 * s, .08, 2.15 * s}, feature.yaw, {187, 151, 105, 255})
        ruins_lab_shaded_box_rotated({p.x, y + .25, p.z}, {1.95 * s, .05, 1.35 * s}, feature.yaw, {78, 107, 105, 255})
        // Short stepped descent characteristic of the sunken court fixture.
        for index in 0 ..< 3 {
            forward := -1.18 * s + f32(index) * .34 * s
            step := ruins_lab_prop_local({position = p, yaw = feature.yaw}, y, 0, .25 + f32(index) * .055, forward)
            ruins_lab_shaded_box_rotated(step, {1.35 * s, .11, .38 * s}, feature.yaw, {174, 146, 105, 255})
        }
    }
}

ruins_lab_court :: proc(plan: ruins.Plan, court: ruins.Central_Court) {
    p := court.center
    y := court.base_y
    // The court is also a shallow built terrace, allowing its shared surface
    // to remain legible on inclined and stepped sites.
    ruins_lab_shaded_box_rotated(
        {p.x, y * .5 + .03, p.z},
        {court.width + .8, y + .12, court.depth + .8},
        court.yaw,
        {128, 116, 88, 255},
    )
    switch plan.culture {
    case .Aegean:
        ruins_lab_shaded_box_rotated(
            {p.x, y + .10, p.z},
            {court.width, .16, court.depth},
            court.yaw,
            {176, 159, 113, 255},
        )
        // Sparse perimeter flags read as an old packed-earth temenos.
        for index in 0 ..< 12 {
            side := index % 4
            along := f32(index / 4 - 1) * 3.6
            x, z := f32(0), f32(0)
            if side == 0 do x, z = along, -court.depth * .5
            if side == 1 do x, z = court.width * .5, along
            if side == 2 do x, z = along, court.depth * .5
            if side == 3 do x, z = -court.width * .5, along
            stone := ruins_lab_prop_local({position = p, yaw = court.yaw}, y, x, .22, z)
            ruins_lab_shaded_box_rotated(
                stone,
                {1.25, .25, .62},
                court.yaw + f32(side % 2) * math.PI * .5,
                {191, 177, 140, 255},
            )
        }
    case .Roman:
        // A coarse grid of surviving paving flags distinguishes a forum-like
        // court without relying on a texture or imported mesh.
        columns := max(int(math.round(court.width / 2.25)), 2)
        rows := max(int(math.round(court.depth / 2.25)), 2)
        cell_width, cell_depth := court.width / f32(columns), court.depth / f32(rows)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                salt := u32(row * columns + column) * 0x9e3779b9
                if ruins.random01(plan.seed ~ salt ~ 0xc047) < .09 do continue
                x := -court.width * .5 + cell_width * (f32(column) + .5)
                z := -court.depth * .5 + cell_depth * (f32(row) + .5)
                flag := ruins_lab_prop_local({position = p, yaw = court.yaw}, y, x, .13, z)
                tone := ruins.random01(plan.seed ~ salt ~ 0xc048)
                color := canvas2d.Color{178, 169, 150, 255}
                if tone < .28 {
                    color = {168, 159, 142, 255}
                } else if tone > .82 {
                    color = {186, 177, 157, 255}
                }
                ruins_lab_shaded_box_rotated(flag, {cell_width - .10, .16, cell_depth - .10}, court.yaw, color)
            }
        }
    case .Minoan:
        ruins_lab_shaded_box_rotated(
            {p.x, y + .11, p.z},
            {court.width, .18, court.depth},
            court.yaw,
            {177, 145, 102, 255},
        )
        // Long contrasting border bands emphasize the north–south ceremonial
        // court proportions found in Minoan palace complexes.
        court_sides := [2]f32{-1, 1}
        for side in court_sides {
            border := ruins_lab_prop_local({position = p, yaw = court.yaw}, y, side * court.width * .45, .23, 0)
            ruins_lab_shaded_box_rotated(border, {.42, .10, court.depth * .92}, court.yaw, {133, 117, 91, 255})
        }
    }
}

ruins_lab_gateway :: proc(plan: ^ruins.Plan) {
    if plan == nil || !plan^.has_gateway do return
    gateway := plan^.gateway
    p := gateway.position
    y := gateway.base_y
    half_opening := gateway.clear_width * .5
    local := ruins.Prop {
        position = p,
        yaw      = gateway.yaw,
    }
    // A thin buried threshold marks the passage while keeping the entire
    // reserved route visually and physically unobstructed.
    threshold := ruins_lab_prop_local(local, y, 0, .045, 0)
    ruins_lab_shaded_box_rotated(
        threshold,
        {gateway.clear_width, .09, min(gateway.depth, f32(1.15))},
        gateway.yaw,
        {162, 149, 119, 255},
    )
    gateway_sides := [2]f32{-1, 1}
    switch gateway.kind {
    case .Aegean_Propylon:
        for side in gateway_sides {
            anta := ruins_lab_prop_local(local, y, side * (half_opening + .72), .55, 0)
            ruins_lab_shaded_box_rotated(anta, {1.35, 1.10, gateway.depth}, gateway.yaw, {184, 172, 143, 255})
            column := ruins_lab_prop_local(local, y, side * (half_opening - .62), .72, -.15)
            ruins_lab_shaded_vertical_prism(column, .62, .62, 1.44, gateway.yaw, {202, 189, 156, 255})
        }
    case .Roman_Gatehouse:
        tower_height := plan^.preservation == .Preserved ? f32(2.35) : f32(1.72)
        if plan^.preservation == .Collapsed do tower_height = 1.05
        for side in gateway_sides {
            tower := ruins_lab_prop_local(local, y, side * (half_opening + 1.2), tower_height * .5, 0)
            ruins_lab_shaded_box_rotated(tower, {2.25, tower_height, gateway.depth}, gateway.yaw, {174, 166, 148, 255})
            inner_pier := ruins_lab_prop_local(local, y, side * (half_opening + .32), .82, -.18)
            ruins_lab_shaded_box_rotated(inner_pier, {.58, 1.64, 1.32}, gateway.yaw, {199, 190, 169, 255})
        }
    case .Minoan_Guardrooms:
        left := ruins_lab_prop_local(local, y, -(half_opening + 1.35), .62, .18)
        right := ruins_lab_prop_local(local, y, half_opening + 1.05, .48, -.28)
        ruins_lab_shaded_box_rotated(left, {2.55, 1.24, gateway.depth * 1.18}, gateway.yaw - .04, {168, 137, 101, 255})
        ruins_lab_shaded_box_rotated(right, {1.95, .96, gateway.depth}, gateway.yaw + .06, {181, 148, 106, 255})
        for side in gateway_sides {
            jamb := ruins_lab_prop_local(local, y, side * (half_opening + .34), .68, 0)
            ruins_lab_shaded_box_rotated(jamb, {.64, 1.36, 1.05}, gateway.yaw, {202, 168, 120, 255})
        }
    }
}

ruins_lab_enclosure :: proc(plan: ^ruins.Plan) {
    if plan == nil do return
    for segment in plan^.enclosure[:plan^.enclosure_count] {
        dx, dz := segment.b.x - segment.a.x, segment.b.z - segment.a.z
        length := math.sqrt(dx * dx + dz * dz)
        target_length := f32(1.55)
        if plan^.culture == .Roman do target_length = 1.18
        if plan^.culture == .Minoan do target_length = 1.85
        chunk_count := max(int(math.ceil(length / target_length)), 1)
        gap_chance := f32(.27)
        if plan^.preservation == .Preserved do gap_chance = .10
        if plan^.preservation == .Collapsed do gap_chance = .48
        for chunk in 0 ..< chunk_count {
            salt := u32(chunk) * 0x9e3779b9
            roll := ruins.random01(segment.seed ~ salt)
            if roll < gap_chance do continue
            t0, t1 := f32(chunk) / f32(chunk_count), f32(chunk + 1) / f32(chunk_count)
            inset := f32(.025)
            t0 += inset / f32(chunk_count)
            t1 -= inset / f32(chunk_count)
            a_y := segment.a_y + (segment.b_y - segment.a_y) * t0
            b_y := segment.a_y + (segment.b_y - segment.a_y) * t1
            height_factor := ruins.random_range(segment.seed ~ salt ~ 2, .52, 1.0)
            if plan^.preservation == .Preserved do height_factor = max(height_factor, f32(.78))
            if plan^.preservation == .Collapsed do height_factor *= .48
            height := max(segment.height * height_factor, f32(.38))
            a := third_person.Vec3{segment.a.x + dx * t0, a_y + height * .5 + .12, segment.a.z + dz * t0}
            b := third_person.Vec3{segment.a.x + dx * t1, b_y + height * .5 + .12, segment.a.z + dz * t1}
            color := canvas2d.Color{171, 158, 128, 255}
            if plan^.culture == .Roman {
                color = chunk % 4 == 1 ? canvas2d.Color{165, 105, 77, 255} : canvas2d.Color{183, 169, 144, 255}
            } else if plan^.culture == .Minoan {
                color = chunk % 3 == 0 ? canvas2d.Color{163, 143, 108, 255} : canvas2d.Color{188, 169, 130, 255}
            }
            ruins_lab_shaded_box_between(a, b, {0, 1, 0}, segment.width, height, color)
            if plan^.preservation == .Collapsed && roll < gap_chance + .16 {
                // A displaced block immediately beside a failing precinct wall.
                midpoint := third_person.Vec3{(a.x + b.x) * .5, min(a_y, b_y) + .20, (a.z + b.z) * .5}
                perpendicular := third_person.Vec3{-dz / max(length, f32(.01)), 0, dx / max(length, f32(.01))}
                midpoint += perpendicular * ruins.random_range(segment.seed ~ salt ~ 3, .55, 1.0)
                ruins_lab_shaded_box_rotated(
                    midpoint,
                    {target_length * .55, .34, segment.width * .88},
                    math.atan2(dz, dx) + ruins.random_range(segment.seed ~ salt ~ 4, -.35, .35),
                    color,
                )
            }
        }
    }
}

ruins_lab_route_graph_node :: proc(graph: ^roads.Graph, point: ruins.Vec2, y, width: f32) -> int {
    if graph == nil do return -1
    for &node, index in graph.nodes[:graph.node_count] {
        dx, dy, dz := node.position.x - point.x, node.position.y - y, node.position.z - point.z
        if dx * dx + dy * dy + dz * dz > .0004 do continue
        node.junction_radius = max(node.junction_radius, width * .62)
        return index
    }
    return roads.add_node(graph, {point.x, y, point.z}, max(width * .62, f32(.72)))
}

ruins_lab_route_pavement :: proc(culture: ruins.Culture) -> roads.Pavement {
    switch culture {
    case .Roman:
        return .Cobblestone
    case .Minoan:
        return .Dirt
    case .Aegean:
        return .Gravel
    }
    return .Dirt
}

ruins_lab_route_surface_color :: proc(culture: ruins.Culture, surface: roads.Surface) -> canvas2d.Color {
    if surface == .Verge {
        switch culture {
        case .Roman:
            return {124, 119, 99, 0}
        case .Minoan:
            return {164, 132, 85, 0}
        case .Aegean:
            return {151, 135, 86, 0}
        }
    }
    if surface == .Shoulder {
        switch culture {
        case .Roman:
            return {158, 151, 132, 220}
        case .Minoan:
            return {202, 171, 119, 235}
        case .Aegean:
            return {171, 153, 104, 215}
        }
    }
    switch culture {
    case .Roman:
        return surface == .Junction ? canvas2d.Color{166, 160, 143, 255} : canvas2d.Color{184, 176, 155, 255}
    case .Minoan:
        return surface == .Junction ? canvas2d.Color{169, 136, 94, 255} : canvas2d.Color{181, 150, 104, 255}
    case .Aegean:
        return surface == .Junction ? canvas2d.Color{181, 162, 108, 255} : canvas2d.Color{194, 174, 120, 255}
    }
    return {181, 150, 104, 255}
}

ruins_lab_road_vertex :: proc(vertex: roads.Vertex, color: canvas2d.Color) -> World_Vertex {
    position := vertex.position
    position.y += .018
    return {
        position,
        world_color(color),
        .Road,
        {vertex.uv[0], vertex.uv[1], f32(vertex.pavement)},
        {vertex.road_half_width, vertex.surface == .Junction ? 1 : 0},
        {vertex.use_intensity, 0},
    }
}

ruins_lab_route_network :: proc(plan: ^ruins.Plan) {
    if plan == nil do return
    graph: roads.Graph
    pavement := ruins_lab_route_pavement(plan^.culture)
    use_intensity := f32(.68)
    if plan^.preservation == .Preserved do use_intensity = .88
    if plan^.preservation == .Collapsed do use_intensity = .42
    for route in plan^.routes[:plan^.route_count] {
        if ruins.route_requires_stairs(plan, route) do continue
        from := ruins_lab_route_graph_node(&graph, route.a, route.a_y, route.width)
        to := ruins_lab_route_graph_node(&graph, route.b, route.b_y, route.width)
        if from < 0 || to < 0 || from == to do continue
        _ = roads.add_straight_edge(&graph, from, to, route.width, .16, pavement, use_intensity)
    }
    if graph.edge_count == 0 do return
    settings := roads.default_bake_settings()
    settings.target_segment_length = 2.1
    settings.target_chunk_length = 32
    settings.surface_lift = .055
    settings.shoulder_drop = .035
    mesh := roads.bake(&graph, settings)
    defer roads.mesh_destroy(&mesh)
    for triangle := 0; triangle + 2 < len(mesh.indices); triangle += 3 {
        a := mesh.vertices[mesh.indices[triangle]]
        b := mesh.vertices[mesh.indices[triangle + 1]]
        c := mesh.vertices[mesh.indices[triangle + 2]]
        append(
            &world_renderer.road_vertices,
            ruins_lab_road_vertex(a, ruins_lab_route_surface_color(plan^.culture, a.surface)),
            ruins_lab_road_vertex(b, ruins_lab_route_surface_color(plan^.culture, b.surface)),
            ruins_lab_road_vertex(c, ruins_lab_route_surface_color(plan^.culture, c.surface)),
        )
    }
}

ruins_lab_route_stairs :: proc(plan: ^ruins.Plan, route: ruins.Route_Segment) {
    if plan == nil || !ruins.route_requires_stairs(plan, route) do return
    path_color := canvas2d.Color{194, 174, 120, 255}
    if plan^.culture == .Roman do path_color = {184, 170, 139, 255}
    if plan^.culture == .Minoan do path_color = {181, 150, 104, 255}
    elevation_change := route.b_y - route.a_y

    // Terrace crossings become discrete flights. Each tread is a shallow box
    // spanning the previous grade to the next, so no gaps open beneath stairs
    // whether the route is traversed uphill or downhill.
    step_count := max(int(math.ceil(math.abs(elevation_change) / .22)), 2)
    dx, dz := route.b.x - route.a.x, route.b.z - route.a.z
    for step in 0 ..< step_count {
        t0, t1 := f32(step) / f32(step_count), f32(step + 1) / f32(step_count)
        y0 := route.a_y + elevation_change * t0
        y1 := route.a_y + elevation_change * t1
        thickness := math.abs(y1 - y0) + .09
        center_y := min(y0, y1) + thickness * .5
        a := third_person.Vec3{route.a.x + dx * t0, center_y, route.a.z + dz * t0}
        b := third_person.Vec3{route.a.x + dx * t1, center_y, route.a.z + dz * t1}
        tread_color := path_color
        if step % 4 == 1 {
            tread_color.r = u8(max(int(tread_color.r) - 8, 0))
            tread_color.g = u8(max(int(tread_color.g) - 7, 0))
            tread_color.b = u8(max(int(tread_color.b) - 5, 0))
        }
        ruins_lab_shaded_box_between(a, b, {0, 1, 0}, route.width, thickness, tread_color)
    }
}

ruins_lab_drainage :: proc(plan: ^ruins.Plan) {
    if plan == nil do return
    for channel in plan^.drainage[:plan^.drainage_count] {
        dx, dz := channel.b.x - channel.a.x, channel.b.z - channel.a.z
        length := math.sqrt(dx * dx + dz * dz)
        if length < .01 do continue
        perpendicular := ruins.Vec2{-dz / length, dx / length}
        yaw := math.atan2(dz, dx)
        bed_color := canvas2d.Color{112, 105, 82, 255}
        edge_color := canvas2d.Color{177, 164, 131, 255}
        if channel.kind == .Capped_Drain {
            bed_color, edge_color = {91, 96, 91, 255}, {181, 171, 151, 255}
        } else if channel.kind == .Plaster_Channel {
            bed_color, edge_color = {79, 108, 108, 255}, {194, 166, 121, 255}
        }
        ruins_lab_shaded_box_between(
            {channel.a.x, channel.a_y + .075, channel.a.z},
            {channel.b.x, channel.b_y + .075, channel.b.z},
            {0, 1, 0},
            channel.width,
            .10,
            bed_color,
        )
        drainage_sides := [2]f32{-1, 1}
        for side in drainage_sides {
            offset := side * (channel.width * .5 + .10)
            ruins_lab_shaded_box_between(
                {channel.a.x + perpendicular.x * offset, channel.a_y + .13, channel.a.z + perpendicular.z * offset},
                {channel.b.x + perpendicular.x * offset, channel.b_y + .13, channel.b.z + perpendicular.z * offset},
                {0, 1, 0},
                .18,
                .20,
                edge_color,
            )
        }
        if channel.kind == .Capped_Drain {
            cap_count := max(int(math.floor(length / .78)), 1)
            missing_chance := f32(.16)
            if plan^.preservation == .Preserved do missing_chance = .04
            if plan^.preservation == .Collapsed do missing_chance = .38
            for cap in 0 ..< cap_count {
                salt := u32(cap) * 0x9e3779b9
                if ruins.random01(channel.seed ~ salt) < missing_chance do continue
                t := (f32(cap) + .5) / f32(cap_count)
                p := third_person.Vec3 {
                    channel.a.x + dx * t,
                    channel.a_y + (channel.b_y - channel.a_y) * t + .20,
                    channel.a.z + dz * t,
                }
                ruins_lab_shaded_box_rotated(
                    p,
                    {.72, .12, channel.width + .26},
                    yaw,
                    cap % 3 == 0 ? canvas2d.Color{197, 187, 165, 255} : canvas2d.Color{169, 160, 143, 255},
                )
            }
        }
    }
}

world_ruins_plan :: proc(plan: ^ruins.Plan, draw_ground: bool, draw_props: bool = true) {
    if plan == nil do return
    if draw_ground {
        extent := plan^.extent
        ruins_lab_shaded_box({0, -.24, 0}, {extent * 2, .44, extent * 2}, {117, 125, 82, 255})
        // A dusty occupation layer keeps the generated footprints readable.
        ruins_lab_shaded_box({0, -.01, 0}, {extent * 1.65, .06, extent * 1.65}, {151, 139, 96, 255})
    }
    if ruins_lab_show_paths {
        ruins_lab_route_network(plan)
        for route in plan^.routes[:plan^.route_count] {
            ruins_lab_route_stairs(plan, route)
        }
    }
    ruins_lab_enclosure(plan)
    ruins_lab_gateway(plan)
    if plan^.mode == .Complex {
        ruins_lab_court(plan^, plan^.court)
        for precinct in plan^.precincts[:plan^.precinct_count] {
            ruins_lab_court(plan^, precinct)
        }
    }
    ruins_lab_drainage(plan)
    for feature in plan^.features[:plan^.feature_count] do ruins_lab_site_feature(feature)
    for building in plan^.buildings[:plan^.building_count] do ruins_lab_building(building)
    if draw_props {
        for prop in plan^.props[:plan^.prop_count] {
            building := plan^.buildings[prop.building]
            ruins_lab_prop(prop, building)
        }
    }
}

world_ruins_lab :: proc(_: ^Editor) {
    world_ruins_plan(&ruins_lab_plan, true, ruins_lab_show_props)
}

ruins_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 900,
        height = 178,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {24, 27, 24, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {197, 166, 105, 255})
    title := fmt.ctprintf("%s RUINS GENERATOR", ruins.culture_name(ruins_lab_culture))
    canvas2d.DrawTextEx(canvas2d.Font{}, title, {38, 38}, 20, 1, {244, 224, 177, 255})
    summary := fmt.ctprintf(
        "%s / %s / %s / %s / %s FINDS   SEED %d   %d STRUCTURES   %d PROPS",
        ruins.mode_name(ruins_lab_mode),
        ruins.terrain_name(ruins_lab_terrain),
        ruins.preservation_name(ruins_lab_preservation),
        ruins.complex_scale_name(ruins_lab_complex_scale),
        ruins.pottery_density_name(ruins_lab_pottery_density),
        ruins_lab_seed,
        ruins_lab_plan.building_count,
        ruins_lab_plan.prop_count,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, summary, {38, 68}, 13, 1, {190, 214, 197, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "1/2 MODE  C CULTURE  T TERRAIN  D DECAY  B SCALE  G FINDS  R SEED  F VIEW  P PROPS  V PATH",
        {38, 91},
        12,
        1,
        {218, 191, 133, 255},
    )
    view_name := cstring("OVERVIEW")
    if ruins_lab_view == .Anchor do view_name = "ANCHOR DETAIL"
    if ruins_lab_view == .Feature do view_name = "COURT FEATURE"
    if ruins_lab_view == .Gateway do view_name = "GATEWAY DETAIL"
    if ruins_lab_view == .Phase do view_name = "OCCUPATION PHASE"
    if ruins_lab_view == .Storage do view_name = "STORAGE DETAIL"
    collapse_degrees := int(math.round(ruins_lab_plan.collapse_yaw * 180 / math.PI))
    if collapse_degrees < 0 do collapse_degrees += 360
    court_count := 0
    if ruins_lab_plan.mode == .Complex {
        court_count = 1 + ruins_lab_plan.precinct_count
    }
    status := fmt.ctprintf(
        "PLAN %s / %s / %d COURTS / %s / %d BRANCHES / WELDED PATH JUNCTIONS / FAILURE %03d DEG",
        ruins_lab_plan.valid ? "VALID" : "INCOMPLETE",
        view_name,
        court_count,
        ruins.precinct_layout_name(ruins_lab_plan.precinct_layout),
        ruins_lab_plan.precinct_count,
        collapse_degrees,
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        status,
        {38, 116},
        11,
        1,
        ruins_lab_plan.valid ? canvas2d.Color{177, 211, 157, 255} : canvas2d.Color{231, 127, 100, 255},
    )
    intact_pottery, sherd_fields, wall_falls, debris_piles, vegetation, stair_flights := 0, 0, 0, 0, 0, 0
    for prop in ruins_lab_plan.props[:ruins_lab_plan.prop_count] {
        if prop.kind == .Pot || prop.kind == .Amphora || prop.kind == .Pithos || prop.kind == .Dolium {
            intact_pottery += 1
        }
        if prop.kind == .Pottery_Sherds do sherd_fields += 1
        if prop.kind == .Tumbled_Wall do wall_falls += 1
        if prop.kind == .Rubble ||
           prop.kind == .Masonry_Pile ||
           prop.kind == .Roof_Tile_Pile ||
           prop.kind == .Fallen_Timber ||
           prop.kind == .Mudbrick_Fall {
            debris_piles += 1
        }
        if prop.kind == .Grass_Tuft || prop.kind == .Scrub do vegetation += 1
    }
    for route in ruins_lab_plan.routes[:ruins_lab_plan.route_count] {
        if ruins.route_requires_stairs(&ruins_lab_plan, route) do stair_flights += 1
    }
    morphology := fmt.ctprintf(
        "SITE FORM %s + %s + %s / SHADED ROUGHNESS %.2f",
        ruins.precinct_layout_name(ruins_lab_plan.precinct_layout),
        ruins.enclosure_layout_name(ruins_lab_plan.enclosure_layout),
        ruins.gateway_kind_name(ruins_lab_plan.gateway.kind),
        RUINS_LAB_MATERIAL_ROUGHNESS,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, morphology, {38, 137}, 10, 1, {202, 189, 155, 255})
    archaeology := fmt.ctprintf(
        "%d VESSELS  %d SHERDS  %d FALLS  %d DEBRIS  %d GROWTH  %d STAIRS  %d DRAINS  %d MOVED",
        intact_pottery,
        sherd_fields,
        wall_falls,
        debris_piles,
        vegetation,
        stair_flights,
        ruins_lab_plan.drainage_count,
        ruins_lab_plan.relocated_prop_count,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, archaeology, {38, 156}, 10, 1, {188, 174, 143, 255})
    _ = width
    _ = height
}
