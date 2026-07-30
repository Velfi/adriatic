package main

import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl3"

LIVE_CONTROL_REQUEST_ENV :: "ADRIATIC_LIVE_CONTROL_REQUEST"
LIVE_CONTROL_RESPONSE_ENV :: "ADRIATIC_LIVE_CONTROL_RESPONSE"
LIVE_CONTROL_DEFAULT_REQUEST_PATH :: "build/live-control.request"
LIVE_CONTROL_DEFAULT_RESPONSE_PATH :: "build/live-control.response"

live_control_path :: proc(environment, fallback: string) -> string {
    path := os.get_env(environment, context.temp_allocator)
    return path != "" ? path : fallback
}

live_control_npc_position :: proc(editor: ^Editor, name: string) -> (third_person.Vec3, string, bool) {
    if strings.equal_fold(name, "Marta") {
        return editor.attendant_position + third_person.Vec3{0, MARTA_STOOL_HEIGHT, 0}, "Marta", true
    }
    if strings.equal_fold(name, "Gerta") {
        return editor.gerta_position + third_person.Vec3{0, MARTA_STOOL_HEIGHT, 0}, "Gerta", true
    }
    residents := [10]story.Resident{.Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena, .Mirna}
    for resident in residents {
        display_name := story.resident_name(resident)
        short_name := resident == .Vesna ? "Vesna" : display_name
        if !strings.equal_fold(name, display_name) && !strings.equal_fold(name, short_name) do continue
        position, found := world_story_resident_position(editor, resident)
        return position, display_name, found
    }
    return {}, "", false
}

live_control_focus_npc :: proc(editor: ^Editor, name: string) -> (string, bool) {
    position, display_name, found := live_control_npc_position(editor, strings.trim_space(name))
    if !found do return "", false
    live_control_focus_position(editor, position)
    return display_name, true
}

live_control_focus_position :: proc(editor: ^Editor, position: third_person.Vec3) {
    editor.camera_target_lock = false
    pose := third_person.camera_near({position.x, position.y + .48, position.z}, {1.35, .62, 1.35})
    third_person.camera_set_pose(&editor.cameras, .Inspection, pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    editor.camera_pose = pose
}

live_control_business_position :: proc(editor: ^Editor, name: string) -> (third_person.Vec3, string, bool) {
    requested := strings.trim_space(name)
    resident: story.Resident
    display_name: string
    if strings.equal_fold(requested, "Pane") ||
       strings.equal_fold(requested, "Bakery") ||
       strings.equal_fold(requested, "West island bakery") {
        resident, display_name = .Niko, "Pane"
    } else if strings.equal_fold(requested, "Fortuna") {
        resident, display_name = .Zora, "Fortuna"
    } else if strings.equal_fold(requested, "Clinica") ||
       strings.equal_fold(requested, "West Clinica") ||
       strings.equal_fold(requested, "West clinic") {
        resident, display_name = .Vesna, "West Clinica"
    } else if strings.equal_fold(requested, "East Clinica") || strings.equal_fold(requested, "East clinic") {
        resident, display_name = .Anica, "East Clinica"
    } else if strings.equal_fold(requested, "Post") ||
       strings.equal_fold(requested, "West Post") ||
       strings.equal_fold(requested, "West post office") {
        resident, display_name = .Toma, "West Post"
    } else if strings.equal_fold(requested, "East Post") || strings.equal_fold(requested, "East post office") {
        resident, display_name = .Lena, "East Post"
    } else if strings.equal_fold(requested, "Aerodromo") ||
       strings.equal_fold(requested, "West Aerodromo") ||
       strings.equal_fold(requested, "West airfield") {
        return editor.attendant_position, "West Aerodromo", true
    } else if strings.equal_fold(requested, "East Aerodromo") || strings.equal_fold(requested, "East airfield") {
        return editor.gerta_position, "East Aerodromo", true
    } else {
        return {}, "", false
    }
    position, _, found := world_story_resident_home_pose(editor, resident)
    return position, display_name, found
}

live_control_focus_business :: proc(editor: ^Editor, name: string) -> (string, bool) {
    position, display_name, found := live_control_business_position(editor, name)
    if !found do return "", false
    live_control_focus_position(editor, position)
    return display_name, true
}

live_control_terrain_brush_name :: proc(editor: ^Editor) -> string {
    switch editor.authoring_tool {
    case .Sculpt:
        return "sculpt"
    case .Smooth:
        return "smooth"
    case .Paint:
        return "paint"
    case .Formations:
        return "formations"
    case .Foliage:
        return "foliage"
    case .Ridge:
        return "ridge"
    case .Cliff:
        return "cliff"
    case .Building:
        return "building"
    case .Marina:
        return "marina"
    case .Farm:
        return "farm"
    case .Wreck:
        return "wreck"
    case .ClimbingLeaves:
        return "climbing_leaves"
    case .Roads:
        return "roads"
    case .GreekAssets:
        return "greek_assets"
    }
    return "unknown"
}

live_control_terrain_brush_response :: proc(editor: ^Editor, request_id: string) -> string {
    radius, strength, hardness, width, height, size := f32(0), f32(0), f32(0), f32(0), f32(0), f32(0)
    mode := ""
    switch editor.authoring_tool {
    case .Sculpt, .Smooth, .Paint:
        radius, strength, hardness = editor.radius, editor.strength, editor.hardness
    case .Formations:
        radius, strength, hardness =
            editor.formation_brush_radius, editor.formation_brush_strength, editor.formation_brush_hardness
    case .Foliage:
        radius, strength, hardness =
            editor.formation_brush_radius, editor.formation_brush_strength, editor.formation_brush_hardness
        mode = editor.foliage_hedgerow_mode ? "hedge" : "mass"
    case .Ridge, .Cliff:
        width, height = editor.curve_width, editor.curve_height
    case .Building:
        radius, strength, hardness =
            settlement_brush_preset_span(editor.architecture_brush_preset) *
            .5,
            editor.architecture_brush_strength,
            editor.architecture_brush_hardness
    case .Marina:
        radius = editor.marina_brush_radius
    case .Farm:
        size = editor.farm_brush_radius * 2
    case .Wreck:
        size = editor.wreck_brush_size
    case .ClimbingLeaves:
        radius, strength, hardness =
            editor.climbing_leaf_brush_radius, editor.climbing_leaf_brush_strength, editor.climbing_leaf_brush_hardness
    case .Roads:
        width = editor.road_width
    case .GreekAssets:
        size = editor.greek_asset_scale
    }
    return fmt.aprintf(
        `{{"ok":true,"id":"%s","tool":"%s","radius":%.3f,"strength":%.3f,"hardness":%.3f,"width":%.3f,"height":%.3f,"size":%.3f,"mode":"%s"}}`,
        request_id,
        live_control_terrain_brush_name(editor),
        radius,
        strength,
        hardness,
        width,
        height,
        size,
        mode,
    )
}

live_control_parse_optional_f32 :: proc(value: string) -> (f32, bool) {
    if value == "-" do return 0, true
    return strconv.parse_f32(value)
}

live_control_audio_status_response :: proc(editor: ^Editor, request_id: string) -> string {
    stream := editor.engine_audio.stream
    queued_bytes, device_id := c.int(-1), sdl.AudioDeviceID(0)
    if stream != nil {
        queued_bytes = sdl.GetAudioStreamQueued(stream)
        device_id = sdl.GetAudioStreamDevice(stream)
    }
    return fmt.aprintf(
        `{{"ok":true,"id":"%s","stream":%v,"device":%d,"queued_bytes":%d,"volume":%.3f,"muted":%v,"main_menu":%v,"pause_screen":"%v","console":%v,"in_map":%v}}`,
        request_id,
        stream != nil,
        device_id,
        queued_bytes,
        editor.gameplay_options.sound_fx_level,
        sound_fx_muted(editor),
        editor.main_menu_active,
        editor.pause_screen,
        editor.console.open,
        editor.in_map,
    )
}

live_control_poll :: proc(editor: ^Editor) {
    request_path := live_control_path(LIVE_CONTROL_REQUEST_ENV, LIVE_CONTROL_DEFAULT_REQUEST_PATH)
    if !os.exists(request_path) do return
    data, read_error := os.read_entire_file_from_path(request_path, context.temp_allocator)
    if read_error != nil do return
    _ = os.remove(request_path)

    request := strings.trim_space(string(data))
    separator := strings.index_byte(request, '\t')
    response_path := live_control_path(LIVE_CONTROL_RESPONSE_ENV, LIVE_CONTROL_DEFAULT_RESPONSE_PATH)
    if separator < 0 {
        _ = os.write_entire_file(response_path, string(`{"ok":false,"error":"malformed request"}`))
        return
    }
    request_id, payload := request[:separator], request[separator + 1:]
    command, arguments := "npc", payload
    if payload == "terrain_brush_get" ||
       payload == "audio_status" ||
       payload == "material_list" ||
       payload == "material_save" ||
       payload == "regenerate_islands" ||
       payload == "rondine_stage" ||
       payload == "gameplay" {
        command, arguments = payload, ""
    } else if command_separator := strings.index_byte(payload, '\t'); command_separator >= 0 {
        command, arguments = payload[:command_separator], payload[command_separator + 1:]
    }
    response: string
    if command == "gameplay" {
        editor.main_menu_active = false
        editor.pause_screen = .Closed
        editor_spawn_into_world(editor)
        response = fmt.aprintf(
            `{{"ok":true,"id":"%s","in_map":%v,"message":"Entered gameplay"}}`,
            request_id,
            editor.in_map,
        )
    } else if command == "rondine_stage" {
        stage_rondine(editor)
        if editor.rondine_visible {
            player_place(
                editor,
                editor.rondine.vehicle.position,
                .Aircraft_Selection,
                editor.rondine.vehicle.yaw_radians,
                false,
            )
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.rondine.vehicle})
            if entered {
                response = fmt.aprintf(`{{"ok":true,"id":"%s","message":"Staged Rondine and entered it"}}`, request_id)
            } else {
                response = fmt.aprintf(
                    `{{"ok":false,"id":"%s","error":"Rondine staged but player could not enter"}}`,
                    request_id,
                )
            }
        } else {
            response = fmt.aprintf(
                `{{"ok":false,"id":"%s","error":"Rondine could not find a clear-water spawn"}}`,
                request_id,
            )
        }
    } else if command == "regenerate_islands" {
        regenerate_default_map(editor)
        response = fmt.aprintf(
            `{{"ok":true,"id":"%s","islands":%d,"message":"Started regenerating both default islands"}}`,
            request_id,
            len(terrain.DEFAULT_ISLAND_SIGNS),
        )
    } else if command == "terrain_brush_get" {
        response = live_control_terrain_brush_response(editor, request_id)
    } else if command == "audio_status" {
        response = live_control_audio_status_response(editor, request_id)
    } else if command == "material_list" {
        names := strings.builder_make(context.temp_allocator)
        for index in 0 ..< int(material_lab.library.count) {
            if index > 0 do strings.write_string(&names, ",")
            fmt.sbprintf(&names, `"%s"`, material_lab_name(&material_lab.library.materials[index]))
        }
        response = fmt.aprintf(
            `{{"ok":true,"id":"%s","active":%d,"materials":[%s]}}`,
            request_id,
            material_lab.selected,
            strings.to_string(names),
        )
    } else if command == "material_attach_map" {
        fields := strings.split(arguments, "\t", context.temp_allocator)
        if len(fields) != 3 {
            response = fmt.aprintf(
                `{{"ok":false,"id":"%s","error":"expected material, map kind, and path"}}`,
                request_id,
            )
        } else if index, attached := material_lab_attach_map(fields[0], fields[1], fields[2]); attached {
            response = fmt.aprintf(
                `{{"ok":true,"id":"%s","material":"%s","index":%d,"map":"%s","path":"%s"}}`,
                request_id,
                material_lab_name(&material_lab.library.materials[index]),
                index,
                fields[1],
                fields[2],
            )
        } else {
            response = fmt.aprintf(
                `{{"ok":false,"id":"%s","error":"material, map kind, or file not found"}}`,
                request_id,
            )
        }
    } else if command == "material_create" {
        fields := strings.split(arguments, "\t", context.temp_allocator)
        red, green, blue: int
        metallic, roughness: f32
        red_ok, green_ok, blue_ok, metallic_ok, roughness_ok: bool
        if len(fields) == 6 {
            red, red_ok = strconv.parse_int(fields[1])
            green, green_ok = strconv.parse_int(fields[2])
            blue, blue_ok = strconv.parse_int(fields[3])
            metallic, metallic_ok = strconv.parse_f32(fields[4])
            roughness, roughness_ok = strconv.parse_f32(fields[5])
        }
        if len(fields) != 6 ||
           !red_ok ||
           !green_ok ||
           !blue_ok ||
           !metallic_ok ||
           !roughness_ok ||
           red < 0 ||
           red > 255 ||
           green < 0 ||
           green > 255 ||
           blue < 0 ||
           blue > 255 ||
           metallic < 0 ||
           metallic > 1 ||
           roughness < .04 ||
           roughness > 1 {
            response = fmt.aprintf(`{{"ok":false,"id":"%s","error":"invalid material settings"}}`, request_id)
        } else if index, created := material_lab_create(
            fields[0],
            {u8(red), u8(green), u8(blue)},
            metallic,
            roughness,
        ); created {
            response = fmt.aprintf(`{{"ok":true,"id":"%s","material":"%s","index":%d}}`, request_id, fields[0], index)
        } else {
            response = fmt.aprintf(
                `{{"ok":false,"id":"%s","error":"material exists, name is empty, or library is full"}}`,
                request_id,
            )
        }
    } else if command == "material_save" {
        if material_lab_save() {
            material_lab.dirty = false
            response = fmt.aprintf(`{{"ok":true,"id":"%s","message":"Material library saved"}}`, request_id)
        } else {
            response = fmt.aprintf(`{{"ok":false,"id":"%s","error":"Material library save failed"}}`, request_id)
        }
    } else if command == "terrain_brush_set" {
        fields := strings.split(arguments, "\t", context.temp_allocator)
        if len(fields) != 8 {
            response = fmt.aprintf(`{{"ok":false,"id":"%s","error":"malformed terrain brush settings"}}`, request_id)
        } else {
            radius, radius_ok := live_control_parse_optional_f32(fields[1])
            strength, strength_ok := live_control_parse_optional_f32(fields[2])
            hardness, hardness_ok := live_control_parse_optional_f32(fields[3])
            width, width_ok := live_control_parse_optional_f32(fields[4])
            height, height_ok := live_control_parse_optional_f32(fields[5])
            size, size_ok := live_control_parse_optional_f32(fields[6])
            tool_ok :=
                fields[0] == "-" ||
                fields[0] == "sculpt" ||
                fields[0] == "smooth" ||
                fields[0] == "paint" ||
                fields[0] == "formations" ||
                fields[0] == "foliage" ||
                fields[0] == "ridge" ||
                fields[0] == "cliff" ||
                fields[0] == "building" ||
                fields[0] == "marina" ||
                fields[0] == "farm" ||
                fields[0] == "wreck" ||
                fields[0] == "climbing_leaves" ||
                fields[0] == "roads" ||
                fields[0] == "greek_assets"
            mode_ok := fields[7] == "-" || fields[7] == "mass" || fields[7] == "hedge"
            if !tool_ok ||
               !radius_ok ||
               !strength_ok ||
               !hardness_ok ||
               !width_ok ||
               !height_ok ||
               !size_ok ||
               !mode_ok {
                response = fmt.aprintf(`{{"ok":false,"id":"%s","error":"invalid terrain brush settings"}}`, request_id)
            } else {
                switch fields[0] {
                case "sculpt":
                    authoring_select_tool(editor, .Sculpt)
                case "smooth":
                    authoring_select_tool(editor, .Smooth)
                case "paint":
                    authoring_select_tool(editor, .Paint)
                case "formations":
                    authoring_select_tool(editor, .Formations)
                case "foliage":
                    authoring_select_tool(editor, .Foliage)
                case "ridge":
                    authoring_select_tool(editor, .Ridge)
                case "cliff":
                    authoring_select_tool(editor, .Cliff)
                case "building":
                    authoring_select_tool(editor, .Building)
                case "marina":
                    authoring_select_tool(editor, .Marina)
                case "farm":
                    authoring_select_tool(editor, .Farm)
                case "wreck":
                    authoring_select_tool(editor, .Wreck)
                case "climbing_leaves":
                    authoring_select_tool(editor, .ClimbingLeaves)
                case "roads":
                    authoring_select_tool(editor, .Roads)
                case "greek_assets":
                    authoring_select_tool(editor, .GreekAssets)
                case "-":
                }
                switch editor.authoring_tool {
                case .Sculpt, .Smooth, .Paint:
                    if fields[1] != "-" do editor.radius = clamp(radius, terrain.BASE_CELL_SIZE, 400)
                    if fields[2] != "-" do editor.strength = clamp(strength, 0, 1)
                    if fields[3] != "-" do editor.hardness = clamp(hardness, 0, 1)
                case .Formations, .Foliage:
                    if fields[1] != "-" {
                        editor.formation_brush_radius = clamp(radius, terrain.BASE_CELL_SIZE, 240)
                    }
                    if fields[2] != "-" do editor.formation_brush_strength = clamp(strength, .02, 1)
                    if fields[3] != "-" do editor.formation_brush_hardness = clamp(hardness, 0, 1)
                    if fields[7] != "-" {
                        editor.foliage_hedgerow_mode = fields[7] == "hedge"
                    }
                case .Ridge, .Cliff:
                    if fields[4] != "-" {
                        editor.curve_width = clamp(width, terrain.BASE_CELL_SIZE, terrain.BASE_CELL_SIZE * 16)
                    }
                    if fields[5] != "-" {
                        editor.curve_height = clamp(height, terrain.BASE_CELL_SIZE, terrain.BASE_CELL_SIZE * 24)
                    }
                case .Building:
                    if fields[1] != "-" {
                        diameter := radius * 2
                        editor.architecture_brush_preset =
                            diameter < 90 ? Settlement_Brush_Preset.Small : diameter < 170 ? Settlement_Brush_Preset.Medium : Settlement_Brush_Preset.Large
                    }
                    if fields[2] != "-" do editor.architecture_brush_strength = clamp(strength, .02, 1)
                    if fields[3] != "-" do editor.architecture_brush_hardness = clamp(hardness, 0, 1)
                case .Marina:
                // The marina stamp has a fixed authored footprint.
                case .Farm:
                    if fields[6] != "-" {
                        editor.farm_brush_radius = clamp(size * .5, 20, 120)
                        editor.farm_preview_revision = 0
                        editor.farm_preview_valid = false
                    }
                case .Wreck:
                    if fields[6] != "-" {
                        editor.wreck_brush_size = clamp(size, 160, 520)
                        editor.wreck_preview_revision = 0
                        editor.wreck_preview_valid = false
                    }
                case .ClimbingLeaves:
                    if fields[1] != "-" {
                        editor.climbing_leaf_brush_radius = clamp(radius, terrain.BASE_CELL_SIZE, 240)
                    }
                    if fields[2] != "-" do editor.climbing_leaf_brush_strength = clamp(strength, .02, 1)
                    if fields[3] != "-" do editor.climbing_leaf_brush_hardness = clamp(hardness, 0, 1)
                case .Roads:
                    if fields[4] != "-" do editor.road_width = clamp(width, 2.5, 24)
                case .GreekAssets:
                    if fields[6] != "-" do editor.greek_asset_scale = clamp(size, .25, 3)
                }
                tweak_sync_from_editor(editor)
                response = live_control_terrain_brush_response(editor, request_id)
            }
        }
    } else {
        focused_name, focused := live_control_focus_npc(editor, arguments)
        subject, not_found := "npc", "NPC not found or not placed"
        if command == "business" {
            focused_name, focused = live_control_focus_business(editor, arguments)
            subject, not_found = "business", "Business not found or not placed"
        } else if command != "npc" {
            focused = false
            not_found = "Unknown live-control command"
        }
        if focused {
            response = fmt.aprintf(
                `{{"ok":true,"id":"%s","%s":"%s","message":"Focused %s"}}`,
                request_id,
                subject,
                focused_name,
                focused_name,
            )
        } else {
            response = fmt.aprintf(
                `{{"ok":false,"id":"%s","error":"%s","requested":"%s"}}`,
                request_id,
                not_found,
                arguments,
            )
        }
    }
    defer delete(response)
    _ = os.write_entire_file(response_path, transmute([]byte)response)
}
