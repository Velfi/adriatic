package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import canvas2d "zelda_engine:canvas2d"

// Lab scenes are transient, named worlds used for focused visual development.
// A lab owns scene configuration and camera setup; loading one never saves back
// to the ordinary terrain project.

Lab_Configure_Proc :: proc(editor: ^Editor, target: string) -> bool
Lab_World_Proc :: proc(editor: ^Editor)
Lab_Input_Proc :: proc(editor: ^Editor)
Lab_UI_Proc :: proc(editor: ^Editor, width, height: i32)
Lab_Exit_Proc :: proc(editor: ^Editor)

LAB_MOUSE_KEY_CAPACITY :: 20

lab_mouse_keys :: proc(keys: ^[LAB_MOUSE_KEY_CAPACITY]canvas2d.KeyboardKey, values: ..canvas2d.KeyboardKey) -> int {
    count := min(len(values), LAB_MOUSE_KEY_CAPACITY)
    for value, index in values[:count] do keys[index] = value
    return count
}

lab_mouse_control_keys :: proc(name: string) -> (keys: [LAB_MOUSE_KEY_CAPACITY]canvas2d.KeyboardKey, count: int) {
    switch name {
    case "arch-wall-generator":
        count = lab_mouse_keys(&keys, .S, .LEFT, .RIGHT, .DOWN, .UP, .A, .D)
    case "boid":
        count = lab_mouse_keys(&keys, .SPACE, .R, .V, .W, .C, .N, .ONE, .TWO, .THREE)
    case "bridge-generator":
        count = lab_mouse_keys(&keys, .A, .D, .S, .R, .LEFT, .RIGHT, .DOWN, .UP, .ONE, .TWO, .Q, .E, .Z, .X, .C, .U)
    case "car-generator":
        count = lab_mouse_keys(&keys, .G, .R, .ONE, .TWO, .THREE, .FOUR, .W)
    case "car":
        count = lab_mouse_keys(&keys, .ONE, .TWO, .THREE, .FOUR, .R)
    case "cemetery-generator":
        count = lab_mouse_keys(&keys, .A, .D, .S, .M, .N, .V, .G, .LEFT, .RIGHT, .DOWN, .UP)
    case "coastal-ecology":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .R, .SPACE, .Q, .E, .DOWN, .UP, .B, .ONE, .TWO, .THREE)
    case "dialogue-sound", "material":
        count = lab_mouse_keys(&keys, .ESCAPE)
    case "dunes":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .R, .A, .D, .G, .H)
    case "flower-generator":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .A, .W, .ONE, .TWO, .G, .L, .F, .C)
    case "fountain-generator":
        count = lab_mouse_keys(&keys, .A, .D, .S, .LEFT, .RIGHT, .DOWN, .UP, .ONE, .TWO)
    case "umbrella-generator":
        count = lab_mouse_keys(&keys, .A, .D, .S, .LEFT, .RIGHT, .DOWN, .UP, .ONE, .TWO)
    case "garden":
        count = lab_mouse_keys(&keys, .ONE, .TWO, .THREE, .FOUR, .R)
    case "hero-building":
        count = lab_mouse_keys(&keys, .K, .A, .D, .LEFT, .RIGHT, .DOWN, .UP, .ONE, .TWO)
    case "leaf-generator":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .S, .C, .G, .V)
    case "lighthouse":
        count = lab_mouse_keys(&keys, .A, .D, .R, .L, .ONE, .TWO, .THREE)
    case "markov-island":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT)
    case "markov-farmland":
        count = lab_mouse_keys(&keys, .ONE, .TWO, .THREE, .FOUR)
    case "mouse-wheel":
        count = lab_mouse_keys(&keys, .R, .ONE, .TWO, .THREE, .FOUR, .F)
    case "plant-site":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .R)
    case "rainbow":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .DOWN, .UP, .ONE, .TWO, .THREE)
    case "road-planning":
        count = lab_mouse_keys(&keys, .R, .SPACE, .S, .ONE, .TWO, .THREE, .FOUR, .P, .O, .ENTER)
    case "landform-maze":
        count = lab_mouse_keys(&keys, .ENTER, .N, .R, .ONE, .TWO, .THREE, .FOUR)
    case "rock":
        count = lab_mouse_keys(&keys, .E, .M, .ESCAPE)
    case "estuary-delta":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .R, .D, .C)
    case "ruins":
        count = lab_mouse_keys(&keys, .R, .ONE, .TWO, .C, .T, .D, .G, .B, .P, .V, .F)
    case "screen-pops":
        count = lab_mouse_keys(&keys, .SPACE, .R, .T, .ESCAPE)
    case "shadow":
        count = lab_mouse_keys(&keys, .TAB, .L)
    case "spring-river":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .R, .A, .D, .DOWN, .UP)
    case "markov-city", "markov-town", "markov-village", "aegean-city", "aegean-town", "aegean-village":
        count = lab_mouse_keys(&keys, .LEFT, .RIGHT, .DOWN, .UP, .R, .ENTER, .TAB)
    }
    return
}

lab_mouse_key_label :: proc(key: canvas2d.KeyboardKey) -> cstring {
    #partial switch key {
    case .LEFT:
        return "<"
    case .RIGHT:
        return ">"
    case .UP:
        return "UP"
    case .DOWN:
        return "DOWN"
    case .SPACE:
        return "SPACE"
    case .ENTER:
        return "ENTER"
    case .ESCAPE:
        return "ESC"
    case .BACKSPACE:
        return "DELETE"
    case .TAB:
        return "TAB"
    case .ONE:
        return "1"
    case .TWO:
        return "2"
    case .THREE:
        return "3"
    case .FOUR:
        return "4"
    case .A:
        return "A"
    case .B:
        return "B"
    case .C:
        return "C"
    case .D:
        return "D"
    case .E:
        return "E"
    case .F:
        return "F"
    case .G:
        return "G"
    case .H:
        return "H"
    case .I:
        return "I"
    case .K:
        return "K"
    case .L:
        return "L"
    case .M:
        return "M"
    case .N:
        return "N"
    case .O:
        return "O"
    case .P:
        return "P"
    case .Q:
        return "Q"
    case .R:
        return "R"
    case .S:
        return "S"
    case .T:
        return "T"
    case .U:
        return "U"
    case .V:
        return "V"
    case .W:
        return "W"
    case .X:
        return "X"
    case .Z:
        return "Z"
    }
    return "?"
}

lab_mouse_action_label :: proc(name: string, key: canvas2d.KeyboardKey) -> cstring {
    switch name {
    case "arch-wall-generator":
        #partial switch key {case .S:
            return "Next shape"; case .LEFT:
            return "Lower wall"; case .RIGHT:
            return "Raise wall"; case .DOWN:
            return "Thinner wall"; case .UP:
            return "Thicker wall"; case .A:
            return "Fewer arches"; case .D:
            return "More arches"}
    case "boid":
        #partial switch key {case .SPACE:
            return boid_lab_paused ? "Resume" : "Pause"; case .R:
            return "Reset flock"; case .V:
            return boid_lab_show_vectors ? "Hide vectors" : "Show vectors"; case .W:
            return "Next wind"; case .C:
            return boid_lab_follow ? "Show overview" : "Follow boid"; case .N:
            return "Next boid"; case .ONE:
            return "Harbor flock"; case .TWO:
            return "Fishing flock"; case .THREE:
            return "Both flocks"}
    case "bridge-generator":
        #partial switch key {case .A:
            return "Previous seed"; case .D:
            return "Next seed"; case .S:
            return "Next style"; case .R:
            return "Next region"; case .LEFT:
            return "Shorter bridge"; case .RIGHT:
            return "Longer bridge"; case .DOWN:
            return "Fewer spans"; case .UP:
            return "More spans"; case .ONE:
            return "Less clearance"; case .TWO:
            return "More clearance"; case .Q:
            return "Narrower cleft"; case .E:
            return "Wider cleft"; case .Z:
            return "Shallower cleft"; case .X:
            return "Deeper cleft"; case .C:
            return "Toggle cutwaters"; case .U:
            return "Toggle shops"}
    case "car-generator":
        #partial switch key {case .G:
            return "Show gallery"; case .R:
            return "New design"; case .ONE:
            return "Saloon"; case .TWO:
            return "Coupe"; case .THREE:
            return "Roadster"; case .FOUR:
            return "Van"; case .W:
            return "Wagon"}
    case "car":
        #partial switch key {case .ONE:
            return "Asphalt"; case .TWO:
            return "Gravel"; case .THREE:
            return "Cobblestone"; case .FOUR:
            return "Dirt"; case .R:
            return "Reset car"}
    case "cemetery-generator":
        #partial switch key {case .A:
            return "Previous seed"; case .D:
            return "Next seed"; case .S:
            return "Next style"; case .M:
            return "Next memorial"; case .N:
            return "No memorial"; case .V:
            return cemetery_lab_memorial_view ? "Close memorial" : "Memorial view"; case .G:
            return cemetery_lab_marker_view ? "Close marker" : "Marker view"; case .LEFT:
            return "Lower density"; case .RIGHT:
            return "Higher density"; case .DOWN:
            return "Smaller grounds"; case .UP:
            return "Larger grounds"}
    case "coastal-ecology":
        #partial switch key {case .LEFT:
            return "Previous seed"; case .RIGHT:
            return "Next seed"; case .R:
            return "New coastline"; case .SPACE:
            return rocky_beach_tide_running ? "Pause tide" : "Resume tide"; case .Q:
            return "Earlier tide"; case .E:
            return "Later tide"; case .DOWN:
            return "Lower tide range"; case .UP:
            return "Higher tide range"; case .B:
            return rocky_beach_config.biology > .45 ? "Reduce biology" : "Restore biology"; case .ONE:
            return "Rocky headlands"; case .TWO:
            return "Embayed coast"; case .THREE:
            return "Low coast"}
    case "dialogue-sound", "material":
        return "Exit lab"
    case "dunes":
        #partial switch key {case .LEFT:
            return "Previous seed"; case .RIGHT:
            return "Next seed"; case .R:
            return "New dunes"; case .A:
            return "Turn wind left"; case .D:
            return "Turn wind right"; case .G:
            return "Less vegetation"; case .H:
            return "More vegetation"}
    case "flower-generator":
        #partial switch key {case .LEFT:
            return "Previous petal"; case .RIGHT:
            return "Next petal"; case .A:
            return "Change arrangement"; case .W:
            return "Change whorls"; case .ONE:
            return "Fewer petals"; case .TWO:
            return "More petals"; case .G:
            return flower_generator_isolated ? "Show gallery" : "Isolate flower"; case .L:
            return "Next life stage"; case .F:
            return flower_generator_lifecycle_gallery ? "Close lifecycle" : "Lifecycle gallery"; case .C:
            return flower_generator_clustered ? "Separate flowers" : "Cluster flowers"}
    case "fountain-generator":
        #partial switch key {case .A:
            return "Previous seed"; case .D:
            return "Next seed"; case .S:
            return "Next style"; case .LEFT:
            return "Smaller basin"; case .RIGHT:
            return "Larger basin"; case .DOWN:
            return "Fewer jets"; case .UP:
            return "More jets"; case .ONE:
            return "Lower jets"; case .TWO:
            return "Higher jets"}
    case "umbrella-generator":
        #partial switch key {case .A:
            return "Previous seed"; case .D:
            return "Next seed"; case .S:
            return "Change type"; case .LEFT:
            return "Smaller canopy"; case .RIGHT:
            return "Larger canopy"; case .DOWN:
            return "Fewer panels"; case .UP:
            return "More panels"; case .ONE:
            return "Shorter pole"; case .TWO:
            return "Taller pole"}
    case "garden":
        #partial switch key {case .R:
            return "Regenerate"; case .ONE:
            return "Courtyard"; case .TWO:
            return "Kitchen garden"; case .THREE:
            return "Wild garden"; case .FOUR:
            return "Stone garden"}
    case "hero-building":
        #partial switch key {case .K:
            return "Next building"; case .A:
            return "Previous seed"; case .D:
            return "Next seed"; case .LEFT:
            return "Narrower front"; case .RIGHT:
            return "Wider front"; case .DOWN:
            return "Shallower arcade"; case .UP:
            return "Deeper arcade"; case .ONE:
            return "Fewer bays"; case .TWO:
            return "More bays"}
    case "leaf-generator":
        #partial switch key {case .LEFT:
            return "Previous shape"; case .RIGHT:
            return "Next shape"; case .S:
            return leaf_generator_serration > 0 ? "Smooth edge" : "Serrated edge"; case .C:
            return "Change curl"; case .G:
            return leaf_generator_isolated ? "Show gallery" : "Isolate leaf"; case .V:
            return leaf_generator_veins ? "Hide veins" : "Show veins"}
    case "lighthouse":
        #partial switch key {case .A:
            return "Previous seed"; case .D:
            return "Next seed"; case .R:
            return "Next region"; case .L:
            return lighthouse_lab_night ? "Use daylight" : "Use night light"; case .ONE:
            return "Short tower"; case .TWO:
            return "Medium tower"; case .THREE:
            return "Tall tower"}
    case "markov-island":
        #partial switch key {case .LEFT:
            return "Previous seed"; case .RIGHT:
            return "Next seed"}
    case "markov-farmland":
        #partial switch key {case .ONE:
            return "Flat"; case .TWO:
            return "Terrace"; case .THREE:
            return "Cliff"; case .FOUR:
            return "Incline"}
    case "mouse-wheel":
        #partial switch key {case .R:
            return "Reset sequence"; case .ONE:
            return "Press 1"; case .TWO:
            return "Press 2"; case .THREE:
            return "Press 3"; case .FOUR:
            return "Press 4"; case .F:
            return "Toggle follow"}
    case "plant-generator":
        #partial switch key {
        case .R:
            return "Regenerate"
        case .LEFT:
            return "Younger plant"
        case .RIGHT:
            return "Older plant"
        case .ONE:
            return "Near detail"
        case .TWO:
            return "Medium detail"
        case .THREE:
            return "Far detail"
        case .FOUR:
            return "Show gallery"
        case .UP:
            return(
                plant_generator_isolated < 0 && !plant_generator_succulent_garden && !plant_generator_climbing_garden ? "Scroll up" : "Next species" \
            )
        case .DOWN:
            return(
                plant_generator_isolated < 0 && !plant_generator_succulent_garden && !plant_generator_climbing_garden ? "Scroll down" : "Previous species" \
            )
        }
    case "plant-site":
        #partial switch key {case .LEFT:
            return "Previous species"; case .RIGHT:
            return "Next species"; case .R:
            return "Resample plants"}
    case "rainbow":
        #partial switch key {case .LEFT:
            return "Earlier sun"; case .RIGHT:
            return "Later sun"; case .DOWN:
            return "Less rain"; case .UP:
            return "More rain"; case .ONE:
            return "Dry"; case .TWO:
            return "Shower"; case .THREE:
            return "Double bow"}
    case "road-planning":
        #partial switch key {case .R:
            return "New terrain"; case .SPACE:
            return "Rebuild route"; case .S:
            return "Next pavement"; case .ONE:
            return "Recommended"; case .TWO:
            return "Cheapest"; case .THREE:
            return "Fastest"; case .FOUR:
            return "Lightest impact"; case .P:
            return road_planning_lab.paused ? "Resume optimizer" : "Pause optimizer"; case .O:
            return road_planning_lab.show_all ? "Hide other routes" : "Show all routes"; case .ENTER:
            return "Commit route"}
    case "landform-maze":
        #partial switch key {case .ENTER:
            return landform_maze_lab.flying ? "Edit maze" : "Fly maze"; case .N:
            return "New maze"; case .R:
            return "Restart flight"; case .ONE:
            return "Lower ridges"; case .TWO:
            return "Raise ridges"; case .THREE:
            return "Narrow corridors"; case .FOUR:
            return "Widen corridors"}
    case "rock":
        #partial switch key {case .E:
            return rock_lab.edge_strength > .01 ? "Hide edge wear" : "Show edge wear"; case .M:
            return "Next material"; case .ESCAPE:
            return "Exit lab"}
    case "estuary-delta":
        #partial switch key {case .LEFT:
            return "Previous seed"; case .RIGHT:
            return "Next seed"; case .R:
            return "New estuary"; case .D:
            return "Next data layer"; case .C:
            return "Change view"}
    case "ruins":
        #partial switch key {case .R:
            return "Regenerate"; case .ONE:
            return "Small ruins"; case .TWO:
            return "Large ruins"; case .C:
            return "Next culture"; case .T:
            return "Next terrain"; case .D:
            return "Next decay"; case .G:
            return "Change growth"; case .B:
            return "Change boundary"; case .P:
            return ruins_lab_show_props ? "Hide props" : "Show props"; case .V:
            return ruins_lab_show_paths ? "Hide paths" : "Show paths"; case .F:
            return "Change fog"}
    case "screen-pops":
        #partial switch key {case .SPACE:
            return "Spawn pop"; case .R:
            return "Spawn atlas"; case .T:
            return "Next style"; case .ESCAPE:
            return "Exit lab"}
    case "shadow":
        #partial switch key {case .TAB:
            return "Next test"; case .L:
            return "Toggle light"}
    case "spring-river":
        #partial switch key {case .LEFT:
            return "Previous seed"; case .RIGHT:
            return "Next seed"; case .R:
            return "New river"; case .A:
            return "Less meander"; case .D:
            return "More meander"; case .DOWN:
            return "Less discharge"; case .UP:
            return "More discharge"}
    case "markov-city", "markov-town", "markov-village", "aegean-city", "aegean-town", "aegean-village":
        #partial switch key {case .LEFT:
            return "Previous option"; case .RIGHT:
            return "Next option"; case .DOWN:
            return "Previous setting"; case .UP:
            return "Next setting"; case .R:
            return "Regenerate"; case .ENTER:
            return "Apply"; case .TAB:
            return "Next panel"}
    }
    return lab_mouse_key_label(key)
}

lab_mouse_control_enabled :: proc(name: string, key: canvas2d.KeyboardKey) -> bool {
    if name == "bridge-generator" && key == .U do return bridge_lab_config.archetype == .Venetian_Canal
    if name == "boid" && key == .N do return boid_lab_system.boid_count > 0
    if name == "road-planning" && key == .ENTER {
        return road_planning_lab.optimizer != nil && !road_planning_lab.committed
    }
    return true
}

lab_mouse_control_selected :: proc(name: string, key: canvas2d.KeyboardKey) -> bool {
    switch name {
    case "boid":
        #partial switch key {case .SPACE:
            return boid_lab_paused; case .V:
            return boid_lab_show_vectors; case .C:
            return boid_lab_follow; case .ONE:
            return boid_lab_mode == 1; case .TWO:
            return boid_lab_mode == 2; case .THREE:
            return boid_lab_mode == 0}
    case "car-generator":
        #partial switch key {case .G:
            return car_generator_lab_selected < 0; case .ONE:
            return car_generator_lab_selected == 0; case .TWO:
            return car_generator_lab_selected == 1; case .THREE:
            return car_generator_lab_selected == 2; case .FOUR:
            return car_generator_lab_selected == 3; case .W:
            return car_generator_lab_selected == 4}
    case "car":
        #partial switch key {case .ONE:
            return car_lab_pavement == .Asphalt; case .TWO:
            return car_lab_pavement == .Gravel; case .THREE:
            return car_lab_pavement == .Cobblestone; case .FOUR:
            return car_lab_pavement == .Dirt}
    case "cemetery-generator":
        #partial switch key {case .V:
            return cemetery_lab_memorial_view; case .G:
            return cemetery_lab_marker_view}
    case "coastal-ecology":
        if key == .SPACE do return !rocky_beach_tide_running
    case "flower-generator":
        #partial switch key {case .G:
            return flower_generator_isolated; case .F:
            return flower_generator_lifecycle_gallery; case .C:
            return flower_generator_clustered}
    case "garden":
        #partial switch key {case .ONE:
            return garden_lab_style == .Courtyard; case .TWO:
            return garden_lab_style == .Kitchen; case .THREE:
            return garden_lab_style == .Wild; case .FOUR:
            return garden_lab_style == .Stone}
    case "leaf-generator":
        #partial switch key {case .S:
            return leaf_generator_serration > 0; case .G:
            return leaf_generator_isolated; case .V:
            return leaf_generator_veins}
    case "lighthouse":
        #partial switch key {case .L:
            return lighthouse_lab_night; case .ONE:
            return lighthouse_lab_height_index == 0; case .TWO:
            return lighthouse_lab_height_index == 1; case .THREE:
            return lighthouse_lab_height_index == 2}
    case "markov-farmland":
        #partial switch key {case .ONE:
            return markov_farmland_lab_terrain == .Flat; case .TWO:
            return markov_farmland_lab_terrain == .Terrace; case .THREE:
            return markov_farmland_lab_terrain == .Cliff; case .FOUR:
            return markov_farmland_lab_terrain == .Incline}
    case "plant-generator":
        #partial switch key {case .ONE:
            return plant_generator_detail == .Near; case .TWO:
            return plant_generator_detail == .Medium; case .THREE:
            return plant_generator_detail == .Far; case .FOUR:
            return plant_generator_isolated < 0}
    case "rainbow":
        #partial switch key {case .ONE:
            return rainbow_lab_rain == 0; case .TWO:
            return rainbow_lab_rain == .68; case .THREE:
            return rainbow_lab_rain == .94}
    case "road-planning":
        #partial switch key {case .ONE:
            return road_planning_lab.alternative == .Recommended; case .TWO:
            return road_planning_lab.alternative == .Cheapest; case .THREE:
            return road_planning_lab.alternative == .Fastest; case .FOUR:
            return road_planning_lab.alternative == .Lightest_Impact; case .P:
            return road_planning_lab.paused; case .O:
            return road_planning_lab.show_all}
    case "rock":
        if key == .E do return rock_lab.edge_strength > .01
    case "ruins":
        #partial switch key {case .P:
            return ruins_lab_show_props; case .V:
            return ruins_lab_show_paths}
    }
    return false
}

lab_mouse_action_page := 0
lab_mouse_action_lab := ""

lab_mouse_control_layout :: proc(
    name: string,
    count, width, height: int,
) -> (
    columns, rows, capacity: int,
    button_width, left: f32,
) {
    columns = clamp((width - 28) / 160, 1, 4)
    rows = clamp((height - 92) / 31, 1, 10)
    capacity = max(columns * rows, 1)
    visible := min(count, capacity)
    columns = max(1, min(columns, (visible + rows - 1) / rows))
    button_width = min(f32(150), (f32(width - 28) - f32(columns - 1) * 10) / f32(columns))
    dock_left := name == "road-planning" || name == "rock" || name == "material"
    left = dock_left ? f32(14) : f32(width - 14) - f32(columns) * button_width - f32(columns - 1) * 10
    return
}

lab_mouse_control_bounds :: proc(name: string, index, count, width, height: int) -> canvas2d.Rectangle {
    columns, rows, _, button_width, left := lab_mouse_control_layout(name, count, width, height)
    column := min(index / rows, columns - 1)
    row := index % rows
    return {left + f32(column) * (button_width + 10), 54 + f32(row * 31), button_width, 25}
}

lab_mouse_page_button_bounds :: proc(next: bool, width: int) -> canvas2d.Rectangle {
    return {f32(width - (next ? 43 : 73)), 27, 28, 21}
}

lab_mouse_controls_process :: proc(name: string) {
    if !canvas2d.IsMouseButtonPressed(.LEFT) do return
    keys, count := lab_mouse_control_keys(name)
    if count == 0 do return
    if lab_mouse_action_lab != name {
        lab_mouse_action_lab = name
        lab_mouse_action_page = 0
    }
    mouse := canvas2d.GetMousePosition()
    width, height := canvas2d.GetScreenWidth(), canvas2d.GetScreenHeight()
    _, _, capacity, _, _ := lab_mouse_control_layout(name, count, int(width), int(height))
    pages := (count + capacity - 1) / capacity
    lab_mouse_action_page = clamp(lab_mouse_action_page, 0, pages - 1)
    if pages > 1 {
        if canvas2d.CheckCollisionPointRec(mouse, lab_mouse_page_button_bounds(false, int(width))) {
            lab_mouse_action_page = (lab_mouse_action_page + pages - 1) % pages
            canvas2d.ConsumeMouseButtonPressed(.LEFT)
            return
        }
        if canvas2d.CheckCollisionPointRec(mouse, lab_mouse_page_button_bounds(true, int(width))) {
            lab_mouse_action_page = (lab_mouse_action_page + 1) % pages
            canvas2d.ConsumeMouseButtonPressed(.LEFT)
            return
        }
    }
    first := lab_mouse_action_page * capacity
    visible := min(capacity, count - first)
    for local_index in 0 ..< visible {
        index := first + local_index
        if canvas2d.CheckCollisionPointRec(
            mouse,
            lab_mouse_control_bounds(name, local_index, visible, int(width), int(height)),
        ) {
            if lab_mouse_control_enabled(name, keys[index]) do canvas2d.InjectKeyPressed(keys[index])
            canvas2d.ConsumeMouseButtonPressed(.LEFT)
            return
        }
    }
}

lab_mouse_controls_draw :: proc(name: string, width, height: int) {
    if name == "plant-generator" && plant_generator_capture_sheet do return
    keys, count := lab_mouse_control_keys(name)
    if count == 0 do return
    if lab_mouse_action_lab != name {
        lab_mouse_action_lab = name
        lab_mouse_action_page = 0
    }
    columns, rows, capacity, button_width, left := lab_mouse_control_layout(name, count, width, height)
    pages := (count + capacity - 1) / capacity
    lab_mouse_action_page = clamp(lab_mouse_action_page, 0, pages - 1)
    first := lab_mouse_action_page * capacity
    visible := min(capacity, count - first)
    visible_columns := max(1, min(columns, (visible + rows - 1) / rows))
    panel_width := f32(visible_columns) * button_width + f32(visible_columns - 1) * 10 + 20
    panel := canvas2d.Rectangle{left - 10, 22, panel_width, 42 + f32(min(rows, visible) * 31)}
    canvas2d.DrawRectangleRounded(panel, .08, 8, {20, 27, 25, 218})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .08, 8, 1, {107, 121, 104, 235})
    canvas2d.DrawTextEx(canvas2d.Font{}, "ACTIONS", {left, 32}, 10, 1, {196, 207, 198, 255})
    if pages > 1 {
        page_directions := [2]bool{false, true}
        for next in page_directions {
            bounds := lab_mouse_page_button_bounds(next, width)
            canvas2d.DrawRectangleRounded(bounds, .18, 6, {39, 47, 44, 244})
            canvas2d.DrawRectangleRoundedLinesEx(bounds, .18, 6, 1, {107, 121, 104, 255})
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                next ? ">" : "<",
                {bounds.x + 10, bounds.y + 5},
                11,
                1,
                {232, 224, 189, 255},
            )
        }
    }
    mouse := canvas2d.GetMousePosition()
    for local_index in 0 ..< visible {
        index := first + local_index
        bounds := lab_mouse_control_bounds(name, local_index, visible, width, height)
        hovered := canvas2d.CheckCollisionPointRec(mouse, bounds)
        enabled := lab_mouse_control_enabled(name, keys[index])
        selected := lab_mouse_control_selected(name, keys[index])
        fill :=
            !enabled ? canvas2d.Color{25, 29, 28, 205} : (hovered ? canvas2d.Color{67, 78, 71, 242} : (selected ? canvas2d.Color{52, 72, 61, 242} : canvas2d.Color{29, 35, 33, 226}))
        canvas2d.DrawRectangleRounded(bounds, .14, 6, fill)
        border :=
            selected ? canvas2d.Color{184, 207, 174, 255} : (enabled ? canvas2d.Color{137, 151, 126, 255} : canvas2d.Color{75, 82, 77, 220})
        canvas2d.DrawRectangleRoundedLinesEx(bounds, .14, 6, 1, border)
        label := lab_mouse_action_label(name, keys[index])
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            label,
            {bounds.x + 10, bounds.y + 7},
            11,
            1,
            enabled ? canvas2d.Color{232, 224, 189, 255} : canvas2d.Color{117, 120, 111, 255},
        )
    }
}

Lab_Scene_Definition :: struct {
    name:                            string,
    configure:                       Lab_Configure_Proc,
    world_overlay:                   Lab_World_Proc,
    process_input:                   Lab_Input_Proc,
    draw_ui:                         Lab_UI_Proc,
    exit:                            Lab_Exit_Proc,
    isolate_content:                 bool,
    enter_gameplay:                  bool,
    allow_gameplay:                  bool,
    replace_world:                   bool,
    suppress_hud:                    bool,
    suppress_infrastructure:         bool,
    suppress_procedural_circulation: bool,
    suppress_shadows:                bool,
}

Lab_Scene_Request :: struct {
    definition: ^Lab_Scene_Definition,
    target:     string,
}

LAB_SCENES := [?]Lab_Scene_Definition {
    {
        name = "landform-maze",
        configure = landform_maze_lab_configure,
        process_input = landform_maze_lab_process_input,
        draw_ui = landform_maze_lab_draw_ui,
        exit = landform_maze_lab_exit,
        isolate_content = true,
        enter_gameplay = false,
        allow_gameplay = true,
        replace_world = false,
        suppress_hud = false,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "witch",
        configure = witch_lab_configure,
        world_overlay = world_witch_lab,
        process_input = witch_lab_process_input,
        draw_ui = witch_lab_draw_ui,
        exit = witch_lab_exit,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "aircraft-transform",
        configure = aircraft_transform_lab_configure,
        world_overlay = aircraft_transform_lab_world,
        process_input = aircraft_transform_lab_input,
        draw_ui = aircraft_transform_lab_ui,
        exit = aircraft_transform_lab_exit,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "road-pathing",
        configure = road_pathing_lab_configure,
        world_overlay = world_road_pathing_lab,
        process_input = road_pathing_lab_process_input,
        draw_ui = road_pathing_lab_draw_ui,
        exit = road_pathing_lab_exit,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "road-planning",
        configure = road_planning_lab_configure,
        world_overlay = world_road_planning_lab,
        process_input = road_planning_lab_process_input,
        draw_ui = road_planning_lab_draw_ui,
        exit = road_planning_lab_exit,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "coastal-ecology",
        configure = rocky_beach_lab_configure,
        world_overlay = world_rocky_beach_lab,
        process_input = rocky_beach_lab_process_input,
        draw_ui = rocky_beach_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "estuary-delta",
        configure = estuary_delta_lab_configure,
        world_overlay = world_estuary_delta_lab,
        process_input = estuary_delta_lab_process_input,
        draw_ui = estuary_delta_lab_draw_ui,
        exit = estuary_delta_lab_exit,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "material",
        configure = material_lab_configure,
        world_overlay = world_material_lab,
        process_input = material_lab_process_input,
        draw_ui = material_lab_draw_ui,
        exit = material_lab_exit,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "rock",
        configure = rock_lab_configure,
        world_overlay = world_rock_lab,
        process_input = rock_lab_process_input,
        draw_ui = rock_lab_draw_ui,
        exit = rock_lab_exit,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "dialogue-sound",
        configure = dialogue_sound_lab_configure,
        process_input = dialogue_sound_lab_process_input,
        draw_ui = dialogue_sound_lab_draw_ui,
        exit = dialogue_sound_lab_exit,
        isolate_content = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "screen-pops",
        configure = screen_pops_lab_configure,
        process_input = screen_pops_lab_process_input,
        draw_ui = screen_pops_lab_draw_ui,
        isolate_content = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "markov-wreck",
        configure = markov_wreck_lab_configure,
        world_overlay = world_markov_wreck,
        process_input = markov_wreck_process_input,
        draw_ui = markov_wreck_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
        allow_gameplay = true,
        replace_world = true,
        suppress_hud = false,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "markov-island",
        configure = markov_island_lab_configure,
        process_input = markov_island_lab_process_input,
        draw_ui = markov_island_lab_draw_ui,
        exit = markov_island_lab_exit,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "dunes",
        configure = dunes_lab_configure,
        world_overlay = world_dunes_lab,
        process_input = dunes_lab_process_input,
        draw_ui = dunes_lab_draw_ui,
        exit = dunes_lab_exit,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "spring-river",
        configure = spring_river_lab_configure,
        world_overlay = world_spring_river_lab,
        process_input = spring_river_lab_process_input,
        draw_ui = spring_river_lab_draw_ui,
        exit = spring_river_lab_exit,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "markov-farmland",
        configure = markov_farmland_lab_configure,
        world_overlay = world_markov_farmland,
        process_input = markov_farmland_process_input,
        draw_ui = markov_farmland_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "foliage-transition",
        configure = foliage_transition_lab_configure,
        world_overlay = foliage_transition_lab_world,
        process_input = foliage_transition_lab_process_input,
        draw_ui = foliage_transition_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "markov-marina",
        configure = markov_marina_lab_configure,
        world_overlay = world_markov_marina,
        process_input = markov_marina_process_input,
        draw_ui = markov_marina_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "ruins",
        configure = ruins_lab_configure,
        world_overlay = world_ruins_lab,
        process_input = ruins_lab_process_input,
        draw_ui = ruins_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "markov-city",
        configure = markov_city_lab_configure,
        world_overlay = world_markov_town_wanderers,
        process_input = settlement_lab_process_input,
        draw_ui = settlement_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "markov-town",
        configure = markov_town_lab_configure,
        world_overlay = world_markov_town_wanderers,
        process_input = settlement_lab_process_input,
        draw_ui = settlement_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "markov-village",
        configure = markov_village_lab_configure,
        world_overlay = world_markov_town_wanderers,
        process_input = settlement_lab_process_input,
        draw_ui = settlement_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "aegean-city",
        configure = aegean_city_lab_configure,
        world_overlay = world_markov_town_wanderers,
        process_input = settlement_lab_process_input,
        draw_ui = settlement_lab_draw_ui,
        isolate_content = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "aegean-town",
        configure = aegean_town_lab_configure,
        world_overlay = world_markov_town_wanderers,
        process_input = settlement_lab_process_input,
        draw_ui = settlement_lab_draw_ui,
        isolate_content = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "aegean-village",
        configure = aegean_village_lab_configure,
        world_overlay = world_markov_town_wanderers,
        process_input = settlement_lab_process_input,
        draw_ui = settlement_lab_draw_ui,
        isolate_content = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "rainbow",
        configure = rainbow_lab_configure,
        world_overlay = world_rainbow_lab,
        process_input = rainbow_lab_process_input,
        draw_ui = rainbow_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "shadow",
        configure = shadow_lab_registry_configure,
        world_overlay = world_shadow_lab,
        process_input = shadow_lab_process_input,
        draw_ui = shadow_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
    },
    {
        name = "wildflower",
        configure = wildflower_lab_registry_configure,
        world_overlay = world_wildflower_lab_adapter,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
    },
    {
        name = "boat",
        configure = boat_lab_configure,
        world_overlay = world_boat_lab,
        draw_ui = boat_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
    },
    {
        name = "boid",
        configure = boid_lab_configure,
        world_overlay = world_boid_lab,
        process_input = boid_lab_process_input,
        draw_ui = boid_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
    {
        name = "patio",
        configure = patio_lab_configure,
        world_overlay = world_patio_lab,
        draw_ui = patio_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "garden",
        configure = garden_lab_configure,
        world_overlay = world_garden_lab,
        process_input = garden_lab_process_input,
        draw_ui = garden_lab_draw_ui,
        exit = garden_lab_exit,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "plant-generator",
        configure = plant_generator_lab_configure,
        world_overlay = world_plant_generator_lab,
        process_input = plant_generator_lab_process_input,
        draw_ui = plant_generator_lab_draw_ui,
        exit = plant_generator_lab_exit,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "plant-site",
        configure = plant_site_lab_configure,
        world_overlay = plant_site_lab_world,
        process_input = plant_site_lab_process_input,
        draw_ui = plant_site_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "leaf-generator",
        configure = leaf_generator_lab_configure,
        world_overlay = world_leaf_generator_lab,
        process_input = leaf_generator_lab_process_input,
        draw_ui = leaf_generator_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "flower-generator",
        configure = flower_generator_lab_configure,
        world_overlay = world_flower_generator_lab,
        process_input = flower_generator_lab_process_input,
        draw_ui = flower_generator_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "window-generator",
        configure = window_generator_lab_configure,
        world_overlay = world_window_generator_lab,
        process_input = window_generator_lab_process_input,
        draw_ui = window_generator_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "arch-wall-generator",
        configure = arch_wall_generator_lab_configure,
        world_overlay = world_arch_wall_generator_lab,
        process_input = arch_wall_generator_lab_process_input,
        draw_ui = arch_wall_generator_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "car",
        configure = car_lab_configure,
        process_input = car_lab_process_input,
        draw_ui = car_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        suppress_hud = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "car-generator",
        configure = car_generator_lab_configure,
        world_overlay = world_car_generator_lab,
        process_input = car_generator_lab_process_input,
        draw_ui = car_generator_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "papi",
        configure = papi_lab_configure,
        world_overlay = world_papi_lab,
        process_input = papi_lab_process_input,
        draw_ui = papi_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "lighthouse",
        configure = lighthouse_lab_configure,
        world_overlay = world_lighthouse_lab,
        process_input = lighthouse_lab_process_input,
        draw_ui = lighthouse_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "bridge-generator",
        configure = bridge_generator_lab_configure,
        world_overlay = world_bridge_generator_lab,
        process_input = bridge_generator_lab_process_input,
        draw_ui = bridge_generator_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = false,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "fountain-generator",
        configure = fountain_lab_configure,
        world_overlay = world_fountain_generator_lab,
        process_input = fountain_lab_process_input,
        draw_ui = fountain_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "umbrella-generator",
        configure = umbrella_lab_configure,
        world_overlay = world_umbrella_generator_lab,
        process_input = umbrella_lab_process_input,
        draw_ui = umbrella_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "cemetery-generator",
        configure = cemetery_lab_configure,
        world_overlay = world_cemetery_generator_lab,
        process_input = cemetery_lab_process_input,
        draw_ui = cemetery_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "windmill-generator",
        configure = windmill_lab_configure,
        world_overlay = world_windmill_generator_lab,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "hero-building",
        configure = hero_lab_configure,
        world_overlay = world_hero_building_lab,
        process_input = hero_lab_process_input,
        draw_ui = hero_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "mouse-gait",
        configure = mouse_gait_lab_configure,
        world_overlay = world_mouse_gait_lab,
        draw_ui = mouse_gait_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "mouse-theater",
        configure = mouse_theater_configure,
        world_overlay = world_mouse_theater,
        process_input = mouse_theater_process_input,
        draw_ui = mouse_theater_draw_ui,
        exit = mouse_theater_exit,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = false,
    },
    {
        name = "mouse-wheel",
        configure = mouse_wheel_lab_configure,
        world_overlay = world_mouse_wheel_lab,
        process_input = mouse_wheel_lab_process_input,
        draw_ui = mouse_wheel_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
    },
    {
        name = "rondine-movement",
        configure = rondine_movement_lab_configure,
        world_overlay = world_rondine_movement_lab,
        draw_ui = rondine_movement_lab_draw_ui,
        isolate_content = true,
        enter_gameplay = true,
        replace_world = true,
        suppress_hud = true,
        suppress_infrastructure = true,
        suppress_procedural_circulation = true,
        suppress_shadows = true,
    },
}

lab_scene_find :: proc(name: string) -> ^Lab_Scene_Definition {
    for &definition in LAB_SCENES {
        if definition.name == name do return &definition
    }
    return nil
}

lab_scene_request_from_args :: proc(args: []string) -> (Lab_Scene_Request, bool) {
    if len(args) < 3 || args[1] != "--lab" do return {}, false
    definition := lab_scene_find(args[2])
    if definition == nil do return {}, false
    return {definition = definition, target = len(args) >= 4 ? args[3] : ""}, true
}

lab_scene_reset_content :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.project.structure_count = 0
    editor.project.next_structure_id = 1
    editor.project.road_graph = {}
    editor.project.city_density = {}
    editor.project.climbing_leaf_density = {}
    architecture.city_plan_destroy(&editor.architecture_city_plan)
    editor.farm_count = 0
    editor.circulation_plan_valid = false
}

lab_scene_load :: proc(editor: ^Editor, request: Lab_Scene_Request) -> bool {
    if editor == nil || request.definition == nil || request.definition.configure == nil do return false
    if editor.active_lab_scene != "" {
        previous := lab_scene_find(editor.active_lab_scene)
        if previous != nil && previous.exit != nil do previous.exit(editor)
    }
    if request.definition.isolate_content do lab_scene_reset_content(editor)
    editor.shadow_lab_scene = false
    editor.wildflower_lab_scene = false
    editor.in_map = request.definition.enter_gameplay
    editor.active_lab_scene = request.definition.name
    if !request.definition.configure(editor, request.target) {
        editor.active_lab_scene = ""
        return false
    }
    editor.project.revision += 1
    return true
}

lab_scene_exit_to_main_menu :: proc(editor: ^Editor) {
    if editor == nil do return
    definition := lab_scene_find(editor.active_lab_scene)
    if definition != nil && definition.exit != nil do definition.exit(editor)
    markov_marina_buoy_physics_destroy(editor)
    editor.active_lab_scene = ""
    editor.shadow_lab_scene = false
    editor.wildflower_lab_scene = false
    editor.capture_world_only = false
    editor.in_map = false
    menu_scene_set(editor, .Closed)
    editor.main_menu_active = true
    editor.main_menu_focus = 0
    third_person.camera_set_active(&editor.cameras, .Player)
    set_pointer_locked(false)
}

lab_scene_destroy_active :: proc(editor: ^Editor) {
    if editor == nil || editor.active_lab_scene == "" do return
    definition := lab_scene_find(editor.active_lab_scene)
    if definition != nil && definition.exit != nil do definition.exit(editor)
    editor.active_lab_scene = ""
}

lab_scene_is_active :: proc(editor: ^Editor, name: string) -> bool {
    return editor != nil && editor.active_lab_scene == name
}

lab_scene_allows_gameplay :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return true
    definition := lab_scene_find(editor.active_lab_scene)
    return definition != nil && definition.allow_gameplay
}

lab_scene_configure_camera :: proc(
    editor: ^Editor,
    focus: third_person.Vec3,
    camera: third_person.Camera,
    enter_gameplay: bool = false,
) {
    if editor == nil do return
    editor.editor_focus = focus
    editor.editor_camera = camera
    editor.camera_pose = third_person.camera_pose(focus, camera)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    editor.in_map = enter_gameplay
    editor.capture_world_only = true
}

lab_scene_draw_world_overlay :: proc(editor: ^Editor) {
    if editor == nil || editor.active_lab_scene == "" do return
    definition := lab_scene_find(editor.active_lab_scene)
    if definition != nil && definition.world_overlay != nil do definition.world_overlay(editor)
}

lab_scene_draw_world :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return false
    if shoreline_harbor_lab_active do return false
    definition := lab_scene_find(editor.active_lab_scene)
    if definition == nil || !definition.replace_world do return false
    if definition.world_overlay != nil do definition.world_overlay(editor)
    return true
}

lab_scene_process_input :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return false
    definition := lab_scene_find(editor.active_lab_scene)
    if definition == nil do return false
    lab_mouse_controls_process(editor.active_lab_scene)
    if definition.process_input != nil do definition.process_input(editor)
    return true
}

lab_scene_draw_ui :: proc(editor: ^Editor, width, height: i32) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return false
    definition := lab_scene_find(editor.active_lab_scene)
    if definition == nil do return false
    if editor.active_lab_scene == "plant-generator" && plant_generator_capture_sheet {
        return definition.suppress_hud
    }
    if definition.draw_ui != nil do definition.draw_ui(editor, width, height)
    lab_mouse_controls_draw(editor.active_lab_scene, int(width), int(height))
    return definition.suppress_hud
}

lab_scene_replaces_world :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return false
    if shoreline_harbor_lab_active do return false
    definition := lab_scene_find(editor.active_lab_scene)
    return definition != nil && definition.replace_world
}

lab_scene_suppresses_infrastructure :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return false
    definition := lab_scene_find(editor.active_lab_scene)
    return definition != nil && definition.suppress_infrastructure
}

lab_scene_suppresses_procedural_circulation :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return false
    definition := lab_scene_find(editor.active_lab_scene)
    return definition != nil && definition.suppress_procedural_circulation
}

lab_scene_suppresses_shadows :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return false
    definition := lab_scene_find(editor.active_lab_scene)
    return definition != nil && definition.suppress_shadows
}

shadow_lab_registry_configure :: proc(editor: ^Editor, _: string) -> bool {
    shadow_lab_configure(editor)
    return true
}

wildflower_lab_registry_configure :: proc(editor: ^Editor, _: string) -> bool {
    configure_wildflower_lab_capture(editor)
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 45)
    atmosphere.set_weather_override(&editor.atmosphere, .Windy)
    editor.atmosphere.weather = atmosphere.weather_for(.Windy)
    editor.atmosphere.front_seconds = 1.6
    editor.atmosphere.paused = true
    return true
}

world_wildflower_lab_adapter :: proc(_: ^Editor) {
    world_wildflower_lab()
}
