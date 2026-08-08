package main

import atmosphere "../packages/atmosphere"
import hero "../packages/hero_buildings"
import "core:fmt"
import "core:math"
import canvas "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

hero_lab_kind := hero.Kind.Post_Office
hero_lab_seed := u32(0x504f5354)
hero_lab_frontage := f32(24)
hero_lab_depth := f32(15)
hero_lab_arcade_depth := f32(6.2)
hero_lab_bays := 5
hero_lab_height := f32(4.8)

hero_lab_plan :: proc() -> hero.Plan {
    return hero.generate(hero_lab_seed, {
        kind          = hero_lab_kind,
        frontage      = hero_lab_frontage,
        depth         = hero_lab_depth,
        arcade_depth  = hero_lab_arcade_depth,
        bay_count     = hero_lab_bays,
        arcade_height = hero_lab_height,
    })
}

hero_lab_camera :: proc(editor: ^Editor) {
    plan := hero_lab_plan()
    distance := max(plan.frontage * .72, f32(18))
    editor.camera_pose = third_person.camera_look_at(
        {distance * .48, plan.arcade_height * .88, distance * 1.04},
        {0, plan.arcade_height * .48, plan.depth * .10},
    )
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

hero_lab_set_defaults :: proc(kind: hero.Kind, seed: u32) {
    config := hero.defaults(kind)
    hero_lab_kind = kind
    hero_lab_seed = seed
    hero_lab_frontage = config.frontage
    hero_lab_depth = config.depth
    hero_lab_arcade_depth = config.arcade_depth
    hero_lab_bays = config.bay_count
    hero_lab_height = config.arcade_height
}

hero_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    hero_lab_seed = 0x504f5354
    hero_lab_kind = .Post_Office
    hero_lab_frontage = 24
    hero_lab_depth = 15
    hero_lab_arcade_depth = 6.2
    hero_lab_bays = 5
    hero_lab_height = 4.8
    switch target {
    case "", "post-office", "civic":
    case "compact":
        hero_lab_frontage = 18
        hero_lab_depth = 12
        hero_lab_arcade_depth = 4.8
        hero_lab_bays = 3
    case "grand":
        hero_lab_frontage = 31
        hero_lab_depth = 19
        hero_lab_arcade_depth = 7.7
        hero_lab_bays = 7
    case "clock":
        hero_lab_seed = 0x504f5355
    case "mailboxes":
        hero_lab_seed = 0x504f5356
    case "airport", "airport-terminal", "aerodromo":
        config := hero.defaults(.Airport_Terminal)
        hero_lab_kind = .Airport_Terminal
        hero_lab_seed = 0x41495254
        hero_lab_frontage = config.frontage
        hero_lab_depth = config.depth
        hero_lab_arcade_depth = config.arcade_depth
        hero_lab_bays = config.bay_count
        hero_lab_height = config.arcade_height
    case "airport-compact":
        hero_lab_kind = .Airport_Terminal
        hero_lab_seed = 0x41495243
        hero_lab_frontage = 24
        hero_lab_depth = 15
        hero_lab_arcade_depth = 6.2
        hero_lab_bays = 6
        hero_lab_height = 4.7
    case "airport-grand":
        hero_lab_kind = .Airport_Terminal
        hero_lab_seed = 0x41495247
        hero_lab_frontage = 34
        hero_lab_depth = 22
        hero_lab_arcade_depth = 8.6
        hero_lab_bays = 8
        hero_lab_height = 5.5
    case "clinic", "clinica":
        hero_lab_set_defaults(.Clinic, 0x434c494e)
    case "clinic-split":
        hero_lab_set_defaults(.Clinic, 0x434c4949)
    case "clinic-side":
        hero_lab_set_defaults(.Clinic, 0x434c4955)
    case "clinic-twin":
        hero_lab_set_defaults(.Clinic, 0x434c494a)
    case "clinic-compact":
        hero_lab_kind = .Clinic
        hero_lab_seed = 0x434c4943
        hero_lab_frontage = 20
        hero_lab_depth = 13
        hero_lab_arcade_depth = 5.2
        hero_lab_bays = 5
        hero_lab_height = 4.5
    case "clinic-grand":
        hero_lab_kind = .Clinic
        hero_lab_seed = 0x434c4947
        hero_lab_frontage = 32
        hero_lab_depth = 20
        hero_lab_arcade_depth = 7.8
        hero_lab_bays = 7
        hero_lab_height = 5.2
    case:
        return false
    }
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 35)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    hero_lab_camera(editor)
    return true
}

hero_lab_process_input :: proc(editor: ^Editor) {
    changed := false
    if canvas.IsKeyPressed(.K) {
        hero_lab_kind = hero.Kind((int(hero_lab_kind) + 1) % len(hero.Kind))
        config := hero.defaults(hero_lab_kind)
        hero_lab_frontage = config.frontage
        hero_lab_depth = config.depth
        hero_lab_arcade_depth = config.arcade_depth
        hero_lab_bays = config.bay_count
        hero_lab_height = config.arcade_height
        changed = true
    }
    if canvas.IsKeyPressed(.A) { hero_lab_seed -= 1; changed = true }
    if canvas.IsKeyPressed(.D) { hero_lab_seed += 1; changed = true }
    if canvas.IsKeyPressed(.LEFT) { hero_lab_frontage = max(f32(16), hero_lab_frontage - 1); changed = true }
    if canvas.IsKeyPressed(.RIGHT) { hero_lab_frontage = min(f32(34), hero_lab_frontage + 1); changed = true }
    if canvas.IsKeyPressed(.DOWN) { hero_lab_arcade_depth = max(f32(4.5), hero_lab_arcade_depth - .4); changed = true }
    if canvas.IsKeyPressed(
        .UP,
    ) { hero_lab_arcade_depth = min(hero_lab_depth * .58, hero_lab_arcade_depth + .4); changed = true }
    if canvas.IsKeyPressed(.ONE) { hero_lab_bays = max(3, hero_lab_bays - 2); changed = true }
    if canvas.IsKeyPressed(.TWO) { hero_lab_bays = min(7, hero_lab_bays + 2); changed = true }
    if changed do hero_lab_camera(editor)
}

hero_lab_material_box :: proc(center, size: third_person.Vec3, material: Settlement_Material) {
    world_settlement_material_box_rotated(center, size, 0, material)
}

hero_lab_pier :: proc(x, z, height, width, depth: f32, shaft_material, trim_material: Settlement_Material) {
    base_height := f32(.30)
    capital_height := f32(.24)
    hero_lab_material_box({x, base_height * .5, z}, {width + .30, base_height, depth + .22}, trim_material)
    hero_lab_material_box(
        {x, base_height + (height - base_height - capital_height) * .5, z},
        {width, height - base_height - capital_height, depth},
        shaft_material,
    )
    hero_lab_material_box(
        {x, height - capital_height * .5, z},
        {width + .38, capital_height, depth + .28},
        trim_material,
    )
}

hero_lab_building :: proc(plan: ^hero.Plan) {
    enamel_material := plan.kind == .Post_Office ? Settlement_Material.Postal_Enamel_Red : .Aerodromo_Enamel_Rim
    worktop_material := plan.kind == .Post_Office ? Settlement_Material.Postal_Sorting_Wood : .Counter_Worktop_Laminate
    // Like the airport terminal, the post office is one continuous roofed
    // public room. There is no enclosed sorting hall or rear façade: people,
    // sea air, and sightlines can pass through the full depth of the building.
    floor_z := f32(0)
    hero_lab_material_box({0, .04, 0}, {plan.frontage + 1.4, .08, plan.depth + 1.2}, .Arcade_Terrazzo)
    for bay in 0 ..< plan.bay_count {
        x := -plan.frontage * .5 + (f32(bay) + .5) * plan.bay_width
        hero_lab_material_box(
            {x, .075, plan.depth * .5 + 1.15},
            {plan.bay_width * .68, .035, 1.7},
            .Exterior_Forecourt_Paving,
        )
    }
    front_z := plan.depth * .5 - plan.pier_depth * .5
    rear_z := -plan.depth * .5 + plan.pier_depth * .5
    for bay in 0 ..= plan.bay_count {
        x := -plan.frontage * .5 + f32(bay) * plan.bay_width
        hero_lab_pier(
            x,
            front_z,
            plan.arcade_height,
            plan.pier_width * .78,
            plan.pier_depth * .82,
            .Pale_Adriatic_Limestone,
            .Exposed_Salted_Limestone,
        )
        hero_lab_pier(
            x,
            rear_z,
            plan.arcade_height,
            plan.pier_width * .78,
            plan.pier_depth * .82,
            .Pale_Adriatic_Limestone,
            .Exposed_Salted_Limestone,
        )
    }
    hero_lab_material_box(
        {0, plan.arcade_height - .18, front_z},
        {plan.frontage + .45, .46, plan.pier_depth + .18},
        .Sun_Washed_Stucco,
    )
    hero_lab_material_box(
        {0, plan.arcade_height + .10, front_z + .04},
        {plan.frontage + .82, .14, plan.pier_depth + .28},
        enamel_material,
    )
    hero_lab_material_box(
        {0, plan.arcade_height - .18, rear_z},
        {plan.frontage + .45, .46, plan.pier_depth + .18},
        .Sun_Washed_Stucco,
    )
    hero_lab_material_box(
        {0, plan.arcade_height + plan.roof_height * .5, 0},
        {plan.frontage + plan.roof_overhang * 2, plan.roof_height, plan.depth + plan.roof_overhang * 2},
        .Standing_Seam_Roof,
    )

    monitor_y := plan.arcade_height + plan.roof_height + plan.monitor_height * .5
    for monitor_index in 0 ..< plan.monitor_count {
        monitor_x := plan.monitor_offset_x
        if plan.monitor_count == 2 {
            monitor_x = (f32(monitor_index) * 2 - 1) * plan.frontage * .19
        }
        monitor_panes := max(3, plan.monitor_count == 2 ? plan.bay_count / 2 : plan.bay_count)
        monitor_pane_width := plan.monitor_width / f32(monitor_panes)
        for pane in 0 ..< monitor_panes {
            x := monitor_x - plan.monitor_width * .5 + (f32(pane) + .5) * monitor_pane_width
            for face in -1 ..= 1 {
                if face == 0 do continue
                z := f32(face) * plan.monitor_depth * .5
                hero_lab_material_box(
                    {x, monitor_y, z + f32(face) * .075},
                    {monitor_pane_width - .18, plan.monitor_height - .20, .035},
                    .Monitor_Tinted_Glass,
                )
            }
            hero_lab_material_box(
                {x, monitor_y, 0},
                {.10, plan.monitor_height, plan.monitor_depth},
                .Anodized_Glazing_Frame,
            )
        }
        hero_lab_material_box(
            {monitor_x, monitor_y - plan.monitor_height * .5, 0},
            {plan.monitor_width + .22, .14, plan.monitor_depth + .18},
            .Anodized_Glazing_Frame,
        )
        hero_lab_material_box(
            {monitor_x, monitor_y + plan.monitor_height * .5 + .10, 0},
            {plan.monitor_width + .65, .20, plan.monitor_depth + .55},
            .Standing_Seam_Roof,
        )
    }

    // One compact locked room occupies a rear corner for registered mail,
    // records, and staff storage. It is deliberately offset from the public
    // counter, so the main office remains an open pavilion on every side.
    if plan.has_secure_room {
        secure_width := plan.secure_width
        secure_depth := plan.secure_depth
        secure_height := plan.arcade_height * .68
        for room_index in 0 ..< plan.private_room_count {
            secure_x := f32(0)
            switch plan.room_arrangement {
            case .Split_Corners:
                room_side := plan.private_room_count == 1 || room_index == 0 ? f32(-1) : f32(1)
                secure_x = room_side * (plan.frontage * .5 - secure_width * .5 - plan.pier_width * .70)
            case .Grouped_Left:
                secure_x =
                    -plan.frontage * .5 +
                    secure_width * .5 +
                    plan.pier_width * .70 +
                    f32(room_index) * (secure_width + .46)
            case .Grouped_Right:
                secure_x =
                    plan.frontage * .5 -
                    secure_width * .5 -
                    plan.pier_width * .70 -
                    f32(room_index) * (secure_width + .46)
            }
            secure_z := rear_z + secure_depth * .5 + plan.pier_depth * .56
            wall := f32(.24)
            hero_lab_material_box(
                {secure_x, secure_height * .5, secure_z - secure_depth * .5},
                {secure_width, secure_height, wall},
                .Sun_Washed_Stucco,
            )
            for side in -1 ..= 1 {
                if side == 0 do continue
                hero_lab_material_box(
                    {secure_x + f32(side) * secure_width * .5, secure_height * .5, secure_z},
                    {wall, secure_height, secure_depth},
                    .Sun_Washed_Stucco,
                )
            }
            door_width := min(f32(1.25), secure_width * .30)
            return_width := (secure_width - door_width) * .5
            for side in -1 ..= 1 {
                if side == 0 do continue
                hero_lab_material_box(
                    {
                        secure_x + f32(side) * (door_width + return_width) * .5,
                        secure_height * .5,
                        secure_z + secure_depth * .5,
                    },
                    {return_width, secure_height, wall},
                    .Sun_Washed_Stucco,
                )
            }
            hero_lab_material_box(
                {secure_x, secure_height - .30, secure_z + secure_depth * .5},
                {door_width, .60, wall},
                .Sun_Washed_Stucco,
            )
            hero_lab_material_box(
                {secure_x, (secure_height - .60) * .5, secure_z + secure_depth * .5 + .14},
                {door_width - .10, secure_height - .60, .08},
                .Painted_Steel,
            )
            if plan.kind == .Clinic {
                if room_index == 0 {
                    // Examination couch, readable through the open doorway.
                    hero_lab_material_box(
                        {secure_x, .78, secure_z - .34},
                        {secure_width * .58, .18, secure_depth * .48},
                        .Counter_Worktop_Laminate,
                    )
                    hero_lab_material_box(
                        {secure_x, .43, secure_z - .34},
                        {secure_width * .42, .64, secure_depth * .30},
                        .Painted_Steel,
                    )
                } else {
                    // A small writing desk distinguishes the private office from
                    // the clinical room without adding another public counter.
                    hero_lab_material_box(
                        {secure_x, .76, secure_z - .28},
                        {secure_width * .62, .12, secure_depth * .34},
                        .Bench_Slatted_Hardwood,
                    )
                }
            } else if plan.kind == .Post_Office {
                // Shallow sorting cubbies expose the warm institutional wood
                // through the secure-room doorway without blocking circulation.
                cubby_z := secure_z - secure_depth * .5 + .18
                hero_lab_material_box({secure_x, 1.24, cubby_z}, {secure_width * .76, 2.18, .18}, .Postal_Sorting_Wood)
                for shelf in 0 ..< 4 {
                    shelf_y := .42 + f32(shelf) * .52
                    hero_lab_material_box(
                        {secure_x, shelf_y, cubby_z + .11},
                        {secure_width * .78, .08, .42},
                        .Postal_Sorting_Wood,
                    )
                }
            }
        }
    }

    // Freestanding service furniture keeps the arcade legible as occupied
    // public space without sacrificing its open, cross-ventilated plan.
    if plan.circular_counter {
        COUNTER_SEGMENTS :: 16
        for segment in 0 ..< COUNTER_SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(COUNTER_SEGMENTS)
            x := math.cos(angle) * plan.counter_radius
            z := plan.counter_z + math.sin(angle) * plan.counter_radius
            rotation := angle + math.PI * .5
            world_settlement_material_box_rotated({x, .92, z}, {.76, 1.05, .58}, rotation, .Teal_Counter_Tile)
            world_settlement_material_box_rotated({x, .41, z}, {.77, .12, .60}, rotation, .Counter_Toe_Kick)
            world_settlement_material_box_rotated({x, 1.48, z}, {.82, .10, .76}, rotation, worktop_material)
        }
    } else {
        hero_lab_material_box(
            {0, 1.02, plan.counter_z},
            {plan.counter_width, 1.55, plan.counter_depth},
            .Teal_Counter_Tile,
        )
        hero_lab_material_box(
            {0, .31, plan.counter_z + .01},
            {plan.counter_width + .03, .14, plan.counter_depth + .03},
            .Counter_Toe_Kick,
        )
        hero_lab_material_box(
            {0, 1.83, plan.counter_z + .08},
            {plan.counter_width + .28, .12, plan.counter_depth + .22},
            worktop_material,
        )
        for hatch in 0 ..< 3 {
            x := (f32(hatch) - 1) * plan.counter_width * .28
            hero_lab_material_box(
                {x, 1.22, plan.counter_z + plan.counter_depth * .52},
                {plan.counter_width * .18, .32, .05},
                .Counter_Grout,
            )
        }
        if plan.counter_form == .L_Shaped {
            return_x := plan.counter_return_side * (plan.counter_width * .5 - plan.counter_depth * .5)
            return_z := plan.counter_z + plan.counter_return_depth * .5
            hero_lab_material_box(
                {return_x, 1.02, return_z},
                {plan.counter_depth, 1.55, plan.counter_return_depth},
                .Teal_Counter_Tile,
            )
            hero_lab_material_box(
                {return_x, .31, return_z},
                {plan.counter_depth + .03, .14, plan.counter_return_depth + .03},
                .Counter_Toe_Kick,
            )
            hero_lab_material_box(
                {return_x, 1.83, return_z},
                {plan.counter_depth + .22, .12, plan.counter_return_depth + .22},
                worktop_material,
            )
        }
    }
    if plan.kind == .Clinic {
        tray_x := plan.counter_width * .28
        hero_lab_material_box({tray_x, 1.98, plan.counter_z}, {1.15, .10, .64}, .Painted_Steel)
        hero_lab_material_box({tray_x, 2.05, plan.counter_z}, {.92, .035, .48}, .Aerodromo_Enamel_Face)
    } else {
        scale_x := plan.circular_counter ? plan.counter_radius + 1.55 : plan.counter_width * .31
        hero_lab_material_box({scale_x, 2.02, plan.counter_z}, {1.05, .16, .72}, enamel_material)
        hero_lab_material_box({scale_x, 2.40, plan.counter_z - .12}, {.68, .56, .12}, .Aerodromo_Enamel_Face)
    }

    if plan.side_mailboxes {
        side_x := -plan.frontage * .5 + plan.pier_width * .74
        for row in 0 ..< 2 {
            for box in 0 ..< plan.mailbox_count {
                z := rear_z + .72 + f32(box) * .62
                hero_lab_material_box({side_x + .04, .82 + f32(row) * .62, z}, {.12, .50, .50}, enamel_material)
            }
        }
    }

    sign_z := front_z + plan.pier_depth * .5 + .10
    hero_lab_material_box(
        {0, plan.arcade_height - .62, sign_z - .04},
        {plan.bay_width * .78, 1.34, .16},
        .Exposed_Salted_Limestone,
    )
    hero_lab_material_box(
        {0, plan.arcade_height - .62, sign_z + .05},
        {plan.bay_width * .68, 1.10, .08},
        enamel_material,
    )
    sign_kind := Business_Sign_Kind.Post
    if plan.kind == .Airport_Terminal do sign_kind = .Aerodromo
    if plan.kind == .Clinic do sign_kind = .Clinica
    world_business_sign({0, plan.arcade_height - .62, sign_z + .12}, 0, sign_kind, 1.82)

    // Warm pendants establish a public room beneath the roof after dusk and
    // reinforce the bay rhythm in daylight.
    for bay in 0 ..< plan.bay_count {
        x := -plan.frontage * .5 + (f32(bay) + .5) * plan.bay_width
        hero_lab_material_box({x, plan.arcade_height - .58, floor_z}, {.05, .64, .05}, .Dark_Hardware)
        hero_lab_material_box({x, plan.arcade_height - .94, floor_z}, {.42, .12, .42}, .Dark_Hardware)
        world_vertical_disc_rotated({x, plan.arcade_height - 1.02, floor_z}, .17, .17, .08, 0, {244, 207, 127, 255})
    }

    // Two waiting benches live in the end bays, keeping the central postal
    // counter and cross-arcade route completely open.
    for side in -1 ..= 1 {
        if side == 0 do continue
        bench_rotation := f32(0)
        bench_x := f32(side) * (plan.frontage * .5 - plan.bay_width * .62)
        bench_z := floor_z + plan.arcade_depth * .16
        if plan.waiting_layout == .Side_Rows {
            bench_rotation = math.PI * .5
            bench_x = f32(side) * (plan.frontage * .5 - .85)
            bench_z = 0
        }
        world_settlement_material_box_rotated(
            {bench_x, .58, bench_z},
            {plan.bay_width * .62, .15, .62},
            bench_rotation,
            .Bench_Slatted_Hardwood,
        )
        back_x, back_z := world_rotate_xz(bench_x, bench_z, 0, -.26, bench_rotation)
        world_settlement_material_box_rotated(
            {back_x, 1.04, back_z},
            {plan.bay_width * .62, .72, .12},
            bench_rotation,
            .Bench_Slatted_Hardwood,
        )
        for leg in -1 ..= 1 {
            if leg == 0 do continue
            leg_x, leg_z := world_rotate_xz(bench_x, bench_z, f32(leg) * plan.bay_width * .22, 0, bench_rotation)
            world_settlement_material_box_rotated({leg_x, .29, leg_z}, {.12, .58, .46}, bench_rotation, .Dark_Hardware)
        }
    }
    if plan.clock {
        hero_lab_material_box(
            {plan.frontage * .25, plan.arcade_height - .72, sign_z},
            {1.18, 1.18, .12},
            .Pale_Adriatic_Limestone,
        )
        world_vertical_disc_rotated(
            {plan.frontage * .25, plan.arcade_height - .72, sign_z + .08},
            .46,
            .46,
            .08,
            0,
            {238, 225, 185, 255},
        )
        hero_lab_material_box(
            {plan.frontage * .25, plan.arcade_height - .60, sign_z + .15},
            {.06, .31, .04},
            .Dark_Hardware,
        )
        hero_lab_material_box(
            {plan.frontage * .36 - plan.frontage * .11, plan.arcade_height - .72, sign_z + .16},
            {.30, .05, .04},
            .Dark_Hardware,
        )
    }
}

world_hero_building_lab :: proc(_: ^Editor) {
    plan := hero_lab_plan()
    hero_lab_material_box({0, -.12, 1.0}, {44, .24, 34}, .Exterior_Forecourt_Paving)
    hero_lab_building(&plan)
}

hero_lab_roof_name :: proc(value: hero.Roof_Form) -> cstring {
    switch value {
    case .Centered_Lantern:
        return "CENTER ROOF"
    case .Offset_Lantern:
        return "OFFSET ROOF"
    case .Twin_Lantern:
        return "TWIN ROOF"
    }
    return "ROOF"
}

hero_lab_room_name :: proc(value: hero.Room_Arrangement) -> cstring {
    switch value {
    case .Split_Corners:
        return "SPLIT ROOMS"
    case .Grouped_Left:
        return "LEFT ROOMS"
    case .Grouped_Right:
        return "RIGHT ROOMS"
    }
    return "ROOMS"
}

hero_lab_counter_name :: proc(value: hero.Counter_Form) -> cstring {
    switch value {
    case .Linear:
        return "LINEAR DESK"
    case .L_Shaped:
        return "L DESK"
    case .Circular:
        return "ROUND DESK"
    }
    return "DESK"
}

hero_lab_waiting_name :: proc(value: hero.Waiting_Layout) -> cstring {
    return value == .End_Bays ? "END WAITING" : "SIDE WAITING"
}

hero_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    plan := hero_lab_plan()
    panel := canvas.Rectangle {
        x      = 22,
        y      = 22,
        width  = 585,
        height = 174,
    }
    canvas.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    canvas.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    title: cstring = "HERO BUILDING LAB · POST OFFICE"
    if plan.kind == .Airport_Terminal do title = "HERO BUILDING LAB · AIRPORT TERMINAL"
    if plan.kind == .Clinic do title = "HERO BUILDING LAB · CLINIC"
    canvas.DrawTextEx(canvas.Font{}, title, {38, 38}, 20, 1, {245, 238, 197, 255})
    status := fmt.ctprintf(
        "SEED %08X   %.1f × %.1f   %d BAYS   ARCADE %.1f",
        hero_lab_seed,
        plan.frontage,
        plan.depth,
        plan.bay_count,
        plan.arcade_depth,
    )
    canvas.DrawTextEx(canvas.Font{}, status, {38, 72}, 14, 1, {208, 239, 240, 255})
    canvas.DrawTextEx(
        canvas.Font{},
        "K building     A / D seed     LEFT / RIGHT frontage",
        {38, 104},
        13,
        1,
        {171, 201, 207, 255},
    )
    details: cstring = "UP / DOWN depth   1 / 2 bays   open counter · secure mail room"
    if plan.kind == .Airport_Terminal do details = "UP / DOWN depth   1 / 2 bays   circular check-in · scale"
    if plan.kind == .Clinic do details = "UP / DOWN depth   1 / 2 bays   reception · exam · office"
    canvas.DrawTextEx(canvas.Font{}, details, {38, 130}, 13, 1, {171, 201, 207, 255})
    validation := fmt.ctprintf(
        "%s · %s · %s · %s",
        hero_lab_roof_name(plan.roof_form),
        hero_lab_room_name(plan.room_arrangement),
        hero_lab_counter_name(plan.counter_form),
        hero_lab_waiting_name(plan.waiting_layout),
    )
    canvas.DrawTextEx(
        canvas.Font{},
        validation,
        {38, 158},
        12,
        1,
        plan.valid ? canvas.Color{145, 205, 164, 255} : canvas.Color{235, 98, 80, 255},
    )
    _ = width
    _ = height
}
