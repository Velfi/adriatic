package main

import atmosphere "../packages/atmosphere"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:os"
import "core:strconv"
import canvas2d "zelda_engine:canvas2d"

SHADOW_LAB_COLLECTION_COUNT :: 5
SHADOW_LAB_LIGHTING_COUNT :: 5

SHADOW_LAB_COLLECTION_NAMES := [SHADOW_LAB_COLLECTION_COUNT]string {
    "PLAYGROUND",
    "PRIMITIVES",
    "HEIGHT & SCALE",
    "THIN DETAILS",
    "ORGANIC FORMS",
}

SHADOW_LAB_LIGHTING_NAMES := [SHADOW_LAB_LIGHTING_COUNT]string {
    "MIDDAY / CLEAR",
    "MORNING / CLEAR",
    "GOLDEN HOUR / CLEAR",
    "AFTERNOON / OVERCAST",
    "LOW SUN / STORM",
}

shadow_lab_apply_lighting :: proc(editor: ^Editor) {
    // Avoid exact solar noon: the projected-shadow path has no horizontal
    // direction at 12:00, so its footprint collapses directly under casters.
    minutes := f32(11 * 60 + 15)
    preset := atmosphere.Weather_Preset.Clear
    switch editor.shadow_lab_lighting {
    case 1:
        minutes = 8 * 60 + 15
    case 2:
        minutes = 17 * 60 + 20
    case 3:
        minutes = 14 * 60
        preset = .Windy
    case 4:
        // Keep the sun above the shadow renderer's horizon cutoff while still
        // producing a long, storm-darkened projection.
        minutes = 17 * 60 + 15
        preset = .Storm
    }
    atmosphere.set_world_minutes(&editor.atmosphere, minutes)
    atmosphere.set_weather_override(&editor.atmosphere, preset)
    editor.atmosphere.weather = atmosphere.weather_for(preset)
    editor.atmosphere.paused = true
}

shadow_lab_configure :: proc(editor: ^Editor) {
    editor.shadow_lab_scene = true
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    if requested := os.get_env("ADRIATIC_SHADOW_LAB_LIGHTING", context.temp_allocator); requested != "" {
        if index, ok := strconv.parse_int(requested); ok {
            editor.shadow_lab_lighting = clamp(int(index), 0, SHADOW_LAB_LIGHTING_COUNT - 1)
        }
    }
    editor.project.sea_level = -10
    for &level in editor.project.levels {
        for &height in level.heights do height = 0
    }
    editor.project.revision += 1
    shadow_lab_apply_lighting(editor)

    editor.camera_pose = third_person.camera_look_at({21, 10.5, 19}, {3.5, 3.2, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

shadow_lab_process_input :: proc(editor: ^Editor) {
    if canvas2d.IsKeyPressed(.TAB) {
        direction := shift_key_down() ? -1 : 1
        editor.shadow_lab_collection =
            (editor.shadow_lab_collection + direction + SHADOW_LAB_COLLECTION_COUNT) % SHADOW_LAB_COLLECTION_COUNT
    }
    if canvas2d.IsKeyPressed(.L) {
        direction := shift_key_down() ? -1 : 1
        editor.shadow_lab_lighting =
            (editor.shadow_lab_lighting + direction + SHADOW_LAB_LIGHTING_COUNT) % SHADOW_LAB_LIGHTING_COUNT
        shadow_lab_apply_lighting(editor)
    }
}

shadow_lab_structure :: proc(
    center: third_person.Vec3,
    width, depth, height, rotation: f32,
    kind: terrain.Formation_Kind,
    color: [4]u8,
    seed: u32,
) -> terrain.Structure {
    return {
        center_x = center.x,
        center_z = center.z,
        width = width,
        depth = depth,
        base_y = center.y,
        height = height,
        rotation = rotation,
        color = color,
        kind = kind,
        seed = seed,
    }
}

world_shadow_lab_item :: proc(editor: ^Editor, structure: terrain.Structure) {
    world_formation(structure)
}

world_shadow_lab_shadow_only :: proc(editor: ^Editor, structure: terrain.Structure) {
    // Shadow-only CPU projection fixtures were removed with the legacy shadow
    // path. Dynamic shadow casters come from submitted world geometry.
}

world_shadow_lab_playground :: proc(editor: ^Editor) {
    timber: canvas2d.Color = {126, 77, 45, 255}
    timber_light: canvas2d.Color = {177, 112, 62, 255}
    metal: canvas2d.Color = {73, 126, 139, 255}
    yellow: canvas2d.Color = {225, 177, 63, 255}
    slide: canvas2d.Color = {184, 77, 62, 255}
    forward := third_person.Vec3{0, 0, 1}

    // Four tall posts and two decks produce strong contact shadows and many
    // overlapping vertical/horizontal silhouettes.
    posts := [4]third_person.Vec3{{-8, 3.4, -4}, {-8, 3.4, 4}, {0, 3.4, -4}, {0, 3.4, 4}}
    for post in posts {
        shadow := shadow_lab_structure({post.x, 0, post.z}, .55, .55, 6.8, 0, .Box, {126, 77, 45, 255}, 100)
        world_shadow_lab_shadow_only(editor, shadow)
        world_box(post, {.55, 6.8, .55}, timber)
    }
    world_box({-8, 3.05, 0}, {4.8, .45, 8.8}, timber_light)
    world_box({0, 3.05, 0}, {4.8, .45, 8.8}, timber_light)
    tower_x := [2]f32{-8, 0}
    for x in tower_x {
        world_shadow_lab_shadow_only(
            editor,
            shadow_lab_structure({x, 0, 0}, 4.8, 8.8, 3.3, 0, .Box, {177, 112, 62, 255}, 101),
        )
    }

    // Roof frame: thin sloped members make aliasing and penumbra changes easy
    // to inspect at low sun angles.
    for x in tower_x {
        left := third_person.Vec3{x - 2.4, 6.7, 0}
        ridge := third_person.Vec3{x, 8.25, 0}
        right := third_person.Vec3{x + 2.4, 6.7, 0}
        world_box_between(left, ridge, forward, .28, .28, yellow)
        world_box_between(ridge, right, forward, .28, .28, yellow)
        world_box_between({left.x, left.y, -4}, {ridge.x, ridge.y, -4}, forward, .28, .28, yellow)
        world_box_between({ridge.x, ridge.y, -4}, {right.x, right.y, -4}, forward, .28, .28, yellow)
    }

    // Monkey bars bridge the towers. Closely spaced narrow casters expose
    // shadow merging and temporal instability.
    rail_a := third_person.Vec3{-5.8, 6.2, -4}
    rail_b := third_person.Vec3{-2.2, 6.2, -4}
    world_box_between(rail_a, rail_b, forward, .22, .22, metal)
    rail_a.z = 4
    rail_b.z = 4
    world_box_between(rail_a, rail_b, forward, .22, .22, metal)
    for index in 0 ..= 6 {
        x := -5.8 + f32(index) * .6
        world_box_between({x, 6.2, -4}, {x, 6.2, 4}, {1, 0, 0}, .16, .16, metal)
        world_shadow_lab_shadow_only(
            editor,
            shadow_lab_structure({x, 0, 0}, .18, 8, 6.25, 0, .Box, {73, 126, 139, 255}, u32(110 + index)),
        )
    }

    // Ladder rungs and their uprights test small gaps close to the receiver.
    ladder_z := [2]f32{-4, 4}
    for z in ladder_z {
        world_box_between({-10.35, .2, z}, {-10.35, 3.4, z}, forward, .20, .20, metal)
        world_box_between({-8.75, .2, z}, {-8.75, 3.4, z}, forward, .20, .20, metal)
        for rung in 0 ..< 6 {
            y := .55 + f32(rung) * .52
            world_box_between({-10.35, y, z}, {-8.75, y, z}, forward, .16, .16, yellow)
        }
    }

    // An inclined slide and A-frame braces add broad angled shadows.
    world_box_between({2.1, 3.0, 0}, {8.8, .28, 0}, forward, 2.25, .22, slide)
    world_box_between({2.1, 3.28, -1.1}, {8.8, .55, -1.1}, forward, .18, .34, yellow)
    world_box_between({2.1, 3.28, 1.1}, {8.8, .55, 1.1}, forward, .18, .34, yellow)
    world_shadow_lab_shadow_only(
        editor,
        shadow_lab_structure({5.45, 0, 0}, 8.4, 2.6, 3.3, 0, .Box, {184, 77, 62, 255}, 130),
    )

    // Swing bay: long chains and a low seat provide separated caster/receiver
    // distances in the same view.
    swing_frame_z := [2]f32{-3.2, 3.2}
    for z in swing_frame_z {
        world_box_between({11, 0, z}, {13, 6.2, z}, forward, .32, .32, timber)
        world_box_between({17, 0, z}, {15, 6.2, z}, forward, .32, .32, timber)
    }
    world_box_between({13, 6.2, -3.2}, {15, 6.2, -3.2}, forward, .34, .34, timber_light)
    world_box_between({13, 6.2, 3.2}, {15, 6.2, 3.2}, forward, .34, .34, timber_light)
    world_box_between({14, 6.2, -3.2}, {14, 6.2, 3.2}, {1, 0, 0}, .38, .38, timber_light)
    swing_seat_z := [2]f32{-1.5, 1.5}
    for z in swing_seat_z {
        world_box_between({13.6, 6.0, z}, {13.6, 1.25, z}, forward, .09, .09, metal)
        world_box_between({14.4, 6.0, z}, {14.4, 1.25, z}, forward, .09, .09, metal)
        world_box({14, 1.12, z}, {1.4, .18, .62}, yellow)
    }
}

world_shadow_lab :: proc(editor: ^Editor) {
    center := f32(0)
    ground := f32(0)
    world_box({center, ground - .22, center}, {58, .40, 44}, {190, 183, 164, 255})
    world_box({center, ground - .43, center}, {59, .18, 45}, {91, 88, 82, 255})
    // The ground is a receiver, not a caster. Everything submitted after this
    // point is real playground/test geometry for the mapped shadow pass.
    world_renderer.dynamic_caster_first = len(world_renderer.vertices)

    if editor.shadow_lab_collection == 0 {
        world_shadow_lab_playground(editor)
    } else if editor.shadow_lab_collection == 1 {
        world_shadow_lab_item(
            editor,
            shadow_lab_structure({center - 14, ground, center}, 6, 6, 6, .10, .Box, {206, 112, 79, 255}, 1),
        )
        world_shadow_lab_item(
            editor,
            shadow_lab_structure({center - 4, ground, center}, 7, 7, 7, 0, .Rock, {112, 143, 151, 255}, 2),
        )
        world_shadow_lab_item(
            editor,
            shadow_lab_structure({center + 7, ground, center}, 6, 6, 10, .18, .Spire, {213, 181, 91, 255}, 3),
        )
        world_shadow_lab_item(
            editor,
            shadow_lab_structure({center + 17, ground, center}, 8, 6, 5, -.28, .Box, {116, 157, 104, 255}, 4),
        )
    } else if editor.shadow_lab_collection == 2 {
        for index in 0 ..< 5 {
            height := 2.0 + f32(index) * 2.2
            x := center - 16 + f32(index) * 8
            width := 2.2 + f32(index) * .75
            world_shadow_lab_item(
                editor,
                shadow_lab_structure(
                    {x, ground, center},
                    width,
                    width,
                    height,
                    f32(index) * .17,
                    .Box,
                    {126, u8(135 + index * 14), 174, 255},
                    u32(20 + index),
                ),
            )
        }
    } else if editor.shadow_lab_collection == 3 {
        for index in 0 ..< 7 {
            x := center - 18 + f32(index) * 6
            height := index % 2 == 0 ? f32(8) : f32(4.5)
            world_shadow_lab_item(
                editor,
                shadow_lab_structure(
                    {x, ground, center},
                    .55,
                    3.6,
                    height,
                    f32(index) * .23,
                    .Box,
                    {182, 123, 84, 255},
                    u32(40 + index),
                ),
            )
        }
    } else {
        kinds := [5]terrain.Formation_Kind{.Rock, .Spire, .Foliage, .Rock, .Foliage}
        for index in 0 ..< 5 {
            x := center - 16 + f32(index) * 8
            width := 5.0 + f32(index % 3) * 1.5
            world_shadow_lab_item(
                editor,
                shadow_lab_structure(
                    {x, ground, center},
                    width,
                    width * .82,
                    5 + f32(index % 2) * 4,
                    f32(index) * .41,
                    kinds[index],
                    {91, u8(125 + index * 12), 88, 255},
                    u32(70 + index),
                ),
            )
        }
    }
    world_renderer.dynamic_caster_count = len(world_renderer.vertices) - world_renderer.dynamic_caster_first
}

shadow_lab_draw_ui :: proc(editor: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 390,
        height = 140,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {12, 25, 31, 226})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {122, 163, 164, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "SHADOW TESTING LAB", {38, 38}, 19, 1, {245, 239, 192, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "TAB  COLLECTION  %d/%d  %s",
            editor.shadow_lab_collection + 1,
            SHADOW_LAB_COLLECTION_COUNT,
            SHADOW_LAB_COLLECTION_NAMES[editor.shadow_lab_collection],
        ),
        {38, 70},
        13,
        1,
        {211, 250, 242, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "L    LIGHTING    %d/%d  %s",
            editor.shadow_lab_lighting + 1,
            SHADOW_LAB_LIGHTING_COUNT,
            SHADOW_LAB_LIGHTING_NAMES[editor.shadow_lab_lighting],
        ),
        {38, 94},
        13,
        1,
        {211, 250, 242, 255},
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, "Hold SHIFT to cycle backward", {38, 118}, 11, 1, {164, 190, 190, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf("%d triangles", len(world_renderer.vertices) / 3),
        {38, 136},
        11,
        1,
        {164, 190, 190, 255},
    )
}
