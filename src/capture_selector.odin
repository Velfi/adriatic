package main

import marina "../packages/marina"
import plants "../packages/plants"
import story "../packages/story"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

CAPTURE_SELECTOR_FILTER_CAPACITY :: 8
CAPTURE_SELECTOR_MATCH_CAPACITY :: 2048

Capture_Subject_Kind :: enum {
    Character,
    Vehicle,
    Structure,
    Prop,
    Plant,
    Selection,
}

Capture_Subject :: struct {
    kind:      Capture_Subject_Kind,
    id:        u64,
    name:      string,
    subtype:   string,
    position:  third_person.Vec3,
    half_size: third_person.Vec3,
    yaw:       f32,
    available: bool,
}

Capture_Selector :: struct {
    kind:         Capture_Subject_Kind,
    identity:     string,
    filters:      [CAPTURE_SELECTOR_FILTER_CAPACITY]string,
    filter_count: int,
    pick:         int,
    pick_set:     bool,
}

capture_presentation_valid :: proc(name: string) -> bool {
    return name == "fit" || name == "portrait" || name == "profile" || name == "overhead" || name == "authored"
}

capture_selector_parse :: proc(
    text: string,
    filters: [CAPTURE_SELECTOR_FILTER_CAPACITY]string,
    filter_count: int,
    pick_text: string,
) -> (
    Capture_Selector,
    string,
    bool,
) {
    selector: Capture_Selector
    trimmed := strings.trim_space(text)
    if trimmed == "" do return selector, "selector is empty", false
    separator := strings.index_byte(trimmed, ':')
    kind_name := separator < 0 ? trimmed : trimmed[:separator]
    selector.identity = separator < 0 ? "" : strings.trim_space(trimmed[separator + 1:])
    switch kind_name {
    case "character":
        selector.kind = .Character
    case "vehicle":
        selector.kind = .Vehicle
    case "structure":
        selector.kind = .Structure
    case "prop":
        selector.kind = .Prop
    case "plant":
        selector.kind = .Plant
    case "selection":
        selector.kind = .Selection
        if selector.identity != "" do return selector, "selection does not take an identity", false
    case:
        return selector, fmt.tprintf("unknown selector kind %s", kind_name), false
    }
    if filter_count < 0 || filter_count > len(selector.filters) {
        return selector, "too many selector filters", false
    }
    selector.filter_count = filter_count
    for index in 0 ..< filter_count do selector.filters[index] = filters[index]
    if pick_text != "" {
        selector.pick_set = true
        if pick_text == "first" {
            selector.pick = 0
        } else {
            parsed, ok := strconv.parse_int(pick_text)
            if !ok || parsed < 1 {
                return selector, "--pick must be first or a one-based positive integer", false
            }
            selector.pick = int(parsed) - 1
        }
    }
    for index in 0 ..< selector.filter_count {
        filter := selector.filters[index]
        split := strings.index_byte(filter, '=')
        if split <= 0 || split == len(filter) - 1 {
            return selector, fmt.tprintf("filter must use key=value: %s", filter), false
        }
    }
    return selector, "", true
}

capture_subject_matches_identity :: proc(subject: Capture_Subject, identity: string) -> bool {
    if identity == "" do return true
    if strings.equal_fold(subject.name, identity) || strings.equal_fold(subject.subtype, identity) do return true
    parsed, ok := strconv.parse_u64(identity)
    return ok && subject.id == parsed
}

capture_subject_matches_filter :: proc(subject: Capture_Subject, filter: string) -> bool {
    split := strings.index_byte(filter, '=')
    if split <= 0 || split == len(filter) - 1 do return false
    key, value := filter[:split], filter[split + 1:]
    switch key {
    case "id":
        parsed, ok := strconv.parse_u64(value)
        return ok && subject.id == parsed
    case "name":
        return strings.equal_fold(subject.name, value)
    case "kind", "type", "resident", "archetype":
        return strings.equal_fold(subject.subtype, value)
    case "available":
        return (value == "true" && subject.available) || (value == "false" && !subject.available)
    }
    return false
}

capture_subject_matches :: proc(subject: Capture_Subject, selector: Capture_Selector) -> bool {
    if subject.kind != selector.kind || !capture_subject_matches_identity(subject, selector.identity) do return false
    for index in 0 ..< selector.filter_count {
        filter := selector.filters[index]
        if !capture_subject_matches_filter(subject, filter) do return false
    }
    return true
}

capture_subject_append :: proc(
    matches: ^[CAPTURE_SELECTOR_MATCH_CAPACITY]Capture_Subject,
    count: ^int,
    subject: Capture_Subject,
    selector: Capture_Selector,
) {
    if count^ >= len(matches) || !capture_subject_matches(subject, selector) do return
    matches[count^] = subject
    count^ += 1
}

capture_selector_collect :: proc(
    editor: ^Editor,
    selector: Capture_Selector,
    matches: ^[CAPTURE_SELECTOR_MATCH_CAPACITY]Capture_Subject,
) -> int {
    count := 0
    if editor == nil do return count
    switch selector.kind {
    case .Character:
        player_position := editor.player.position
        capture_subject_append(
            matches,
            &count,
            {
                kind = .Character,
                id = 1,
                name = "player",
                subtype = "player",
                position = player_position,
                half_size = {.42, .72, .35},
                yaw = editor.player.facing_yaw_radians,
                available = true,
            },
            selector,
        )
        for resident in story.Resident {
            position, display_name, found := live_control_npc_position(editor, story.resident_name(resident))
            if !found do continue
            yaw := f32(0)
            if resident != .Marta && resident != .Gerta {
                _, frontage_rotation, home_found := world_story_resident_home_pose(editor, resident)
                if home_found do yaw = frontage_rotation + f32(math.PI * .5)
                if resident == .Zora do yaw -= .10
            }
            capture_subject_append(
                matches,
                &count,
                {
                    kind = .Character,
                    id = 100 + u64(resident),
                    name = display_name,
                    subtype = fmt.tprintf("%v", resident),
                    position = position,
                    half_size = {.42, .72, .35},
                    yaw = yaw,
                    available = true,
                },
                selector,
            )
        }
    case .Vehicle:
        capture_subject_append(
            matches,
            &count,
            {
                kind = .Vehicle,
                id = 1,
                name = "car",
                subtype = "car",
                position = editor.car.position,
                half_size = {1.05, .8, 1.8},
                yaw = editor.car.yaw_radians,
                available = true,
            },
            selector,
        )
        for index in 0 ..< editor.aircraft.count {
            slot := &editor.aircraft.slots[index]
            if slot.vehicle == nil do continue
            // Flight simulation owns the authoritative aircraft transform.
            // The generic vehicle registry is synchronized for interaction,
            // but authored capture setup can move a physics body before that
            // synchronization step runs. Select the live body so inspection
            // cameras never frame the aircraft's stale ground position.
            position := slot.vehicle.position
            #partial switch slot.kind {
            case .Postale:
                position = editor.postale.body.position
            case .Libellula, .Libellula_Mk2:
                position = editor.libellula.body.position
            case .Rondine:
                position = editor.rondine.body.position
            }
            capture_subject_append(
                matches,
                &count,
                {
                    kind = .Vehicle,
                    id = 100 + u64(slot.kind),
                    name = slot.name,
                    subtype = fmt.tprintf("%v", slot.kind),
                    position = position,
                    half_size = {4.5, 2.0, 4.5},
                    yaw = slot.vehicle.yaw_radians,
                    available = slot.available,
                },
                selector,
            )
        }
    case .Structure:
        for index in 0 ..< editor.project.structure_count {
            structure := &editor.project.structures[index]
            capture_subject_append(
                matches,
                &count,
                {
                    kind = .Structure,
                    id = structure.id,
                    name = fmt.tprintf("structure-%d", structure.id),
                    subtype = fmt.tprintf("%v", structure.building.archetype),
                    position = {structure.center_x, structure.base_y + structure.height * .5, structure.center_z},
                    half_size = {structure.width * .5, structure.height * .5, structure.depth * .5},
                    yaw = structure.rotation,
                    available = true,
                },
                selector,
            )
        }
    case .Selection:
        if editor.structure_selected >= 0 && editor.structure_selected < editor.project.structure_count {
            structure := &editor.project.structures[editor.structure_selected]
            capture_subject_append(
                matches,
                &count,
                {
                    kind = .Selection,
                    id = structure.id,
                    name = fmt.tprintf("structure-%d", structure.id),
                    subtype = fmt.tprintf("%v", structure.building.archetype),
                    position = {structure.center_x, structure.base_y + structure.height * .5, structure.center_z},
                    half_size = {structure.width * .5, structure.height * .5, structure.depth * .5},
                    yaw = structure.rotation,
                    available = true,
                },
                selector,
            )
        }
    case .Prop:
        if editor.active_lab_scene == "ruins" {
            for index in 0 ..< ruins_lab_plan.prop_count {
                prop := &ruins_lab_plan.props[index]
                base_y := f32(0)
                if prop.building >= 0 && prop.building < ruins_lab_plan.building_count {
                    base_y = ruins_lab_plan.buildings[prop.building].base_y
                }
                capture_subject_append(
                    matches,
                    &count,
                    {
                        kind = .Prop,
                        id = u64(index + 1),
                        name = fmt.tprintf("%v-%d", prop.kind, index + 1),
                        subtype = fmt.tprintf("%v", prop.kind),
                        position = {prop.position.x, base_y + prop.scale * .5, prop.position.z},
                        half_size = {prop.scale * .75, prop.scale * .75, prop.scale * .75},
                        yaw = prop.yaw,
                        available = true,
                    },
                    selector,
                )
            }
        } else if editor.active_lab_scene == "markov-marina" {
            for index in 0 ..< markov_marina_plan.prop_count {
                prop := &markov_marina_plan.props[index]
                position := marina.plan_world_position(&markov_marina_plan, prop.position)
                capture_subject_append(
                    matches,
                    &count,
                    {
                        kind = .Prop,
                        id = u64(index + 1),
                        name = fmt.tprintf("%v-%d", prop.kind, index + 1),
                        subtype = fmt.tprintf("%v", prop.kind),
                        position = {position.x, .7, position.z},
                        half_size = {1, 1, 1},
                        yaw = marina.plan_world_yaw(&markov_marina_plan, prop.yaw),
                        available = true,
                    },
                    selector,
                )
            }
        }
    case .Plant:
        if plant_generator_isolated >= 0 &&
           plant_generator_isolated < plants.SPECIES_COUNT &&
           plant_generator_ready[plant_generator_isolated] {
            species := plants.Species(plant_generator_isolated)
            generated := &plant_generator_results[plant_generator_isolated].plant
            scale := plant_generator_display_scale(species)
            minimum, maximum := generated.bounds.minimum, generated.bounds.maximum
            capture_subject_append(
                matches,
                &count,
                {
                    kind = .Plant,
                    id = u64(plant_generator_isolated + 1),
                    name = fmt.tprintf("%v", species),
                    subtype = fmt.tprintf("%v", species),
                    position = {
                        (minimum[0] + maximum[0]) * .5 * scale,
                        (minimum[1] + maximum[1]) * .5 * scale,
                        (minimum[2] + maximum[2]) * .5 * scale,
                    },
                    half_size = {
                        (maximum[0] - minimum[0]) * .5 * scale,
                        (maximum[1] - minimum[1]) * .5 * scale,
                        (maximum[2] - minimum[2]) * .5 * scale,
                    },
                    available = true,
                },
                selector,
            )
        }
    }
    return count
}

capture_selector_resolve :: proc(editor: ^Editor, selector: Capture_Selector) -> (Capture_Subject, string, bool) {
    matches: [CAPTURE_SELECTOR_MATCH_CAPACITY]Capture_Subject
    count := capture_selector_collect(editor, selector, &matches)
    if count == 0 do return {}, "selector matched no instantiated subjects", false
    if !selector.pick_set && count != 1 {
        return {}, fmt.tprintf("selector matched %d subjects; use --pick first or --pick N", count), false
    }
    pick := selector.pick_set ? selector.pick : 0
    if pick < 0 || pick >= count {
        return {}, fmt.tprintf("selector pick %d exceeds %d matches", pick + 1, count), false
    }
    return matches[pick], "", true
}

capture_subject_pose :: proc(subject: Capture_Subject, presentation: string) -> (third_person.Camera_Pose, bool) {
    if presentation == "authored" do return {}, false
    focus := subject.position
    extent := max(subject.half_size.x, max(subject.half_size.y, subject.half_size.z))
    distance := max(extent * 3.1, f32(2.4))
    if presentation == "portrait" {
        focus.y += subject.half_size.y * .34
        distance = max(subject.half_size.y * 2.4, f32(1.75))
    }
    forward := third_person.Vec3{math.sin(subject.yaw), 0, math.cos(subject.yaw)}
    right := third_person.Vec3{math.cos(subject.yaw), 0, -math.sin(subject.yaw)}
    eye := focus + forward * distance * .88 + right * distance * .34 + third_person.Vec3{0, distance * .22, 0}
    if presentation == "profile" {
        eye = focus + right * distance + third_person.Vec3{0, distance * .12, 0}
    } else if presentation == "overhead" {
        eye = focus + third_person.Vec3{0, distance, .001}
    }
    return third_person.camera_look_at(eye, focus), true
}

capture_selector_pose :: proc(
    editor: ^Editor,
    selector_text: string,
    filters: [CAPTURE_SELECTOR_FILTER_CAPACITY]string,
    filter_count: int,
    pick: string,
    presentation: string,
) -> (
    third_person.Camera_Pose,
    Capture_Subject,
    string,
    bool,
) {
    selector, parse_error, parsed := capture_selector_parse(selector_text, filters, filter_count, pick)
    if !parsed do return {}, {}, parse_error, false
    subject, resolve_error, resolved := capture_selector_resolve(editor, selector)
    if !resolved do return {}, {}, resolve_error, false
    pose, framed := capture_subject_pose(subject, presentation)
    if !framed do pose = editor.camera_pose
    return pose, subject, "", true
}
