package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"

// Lab scenes are transient, named worlds used for focused visual development.
// A lab owns scene configuration and camera setup; loading one never saves back
// to the ordinary terrain project.

Lab_Configure_Proc :: proc(editor: ^Editor, target: string) -> bool
Lab_World_Proc :: proc(editor: ^Editor)
Lab_Input_Proc :: proc(editor: ^Editor)
Lab_UI_Proc :: proc(editor: ^Editor, width, height: i32)
Lab_Exit_Proc :: proc(editor: ^Editor)

Lab_Scene_Definition :: struct {
    name:                            string,
    configure:                       Lab_Configure_Proc,
    world_overlay:                   Lab_World_Proc,
    process_input:                   Lab_Input_Proc,
    draw_ui:                         Lab_UI_Proc,
    exit:                            Lab_Exit_Proc,
    isolate_content:                 bool,
    enter_gameplay:                  bool,
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
        name = "markov-wreck",
        configure = markov_wreck_lab_configure,
        world_overlay = world_markov_wreck,
        process_input = markov_wreck_process_input,
        draw_ui = markov_wreck_draw_ui,
        isolate_content = true,
        enter_gameplay = false,
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
    editor.pause_screen = .Closed
    editor.main_menu_active = true
    editor.main_menu_focus = 0
    third_person.camera_set_active(&editor.cameras, .Player)
    set_pointer_locked(false)
}

lab_scene_is_active :: proc(editor: ^Editor, name: string) -> bool {
    return editor != nil && editor.active_lab_scene == name
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
    if definition.process_input != nil do definition.process_input(editor)
    return true
}

lab_scene_draw_ui :: proc(editor: ^Editor, width, height: i32) -> bool {
    if editor == nil || editor.active_lab_scene == "" do return false
    definition := lab_scene_find(editor.active_lab_scene)
    if definition == nil do return false
    if definition.draw_ui != nil do definition.draw_ui(editor, width, height)
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
