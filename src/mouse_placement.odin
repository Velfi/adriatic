package main

import story "../packages/story"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:testing"
import canvas2d "zelda_engine:canvas2d"

MOUSE_PLACEMENT_CAPACITY :: 12

Mouse_Placement :: struct {
    resident: story.Resident,
    x, z:     f32,
    rotation: f32,
}

mouse_placement_index :: proc(editor: ^Editor, resident: story.Resident) -> int {
    if editor == nil do return -1
    for placement, index in editor.mouse_placements[:editor.mouse_placement_count] {
        if placement.resident == resident do return index
    }
    return -1
}

mouse_placement_available_count :: proc(editor: ^Editor) -> int {
    if editor == nil do return 0
    return MOUSE_PLACEMENT_CAPACITY - editor.mouse_placement_count
}

mouse_placement_available_at :: proc(editor: ^Editor, available_index: int) -> (story.Resident, bool) {
    if editor == nil || available_index < 0 do return {}, false
    cursor := 0
    for value in 0 ..< MOUSE_PLACEMENT_CAPACITY {
        resident := story.Resident(value)
        if mouse_placement_index(editor, resident) >= 0 do continue
        if cursor == available_index do return resident, true
        cursor += 1
    }
    return {}, false
}

mouse_placement_profile :: proc(resident: story.Resident, position: third_person.Vec3, rotation: f32) -> (Mouse_Model, f32) {
    model := Mouse_Model{position = position, rotation = rotation, grounded = true}
    scale := f32(1)
    switch resident {
    case .Marta: model.build, model.snout_length, model.accessory, model.fur, model.pattern = .94, 1.04, .Goggles, .Chestnut, .Pale_Belly
    case .Gerta: model.build, model.snout_length, model.accessory, model.fur, model.pattern = 1.08, .94, .Flat_Cap, .Silver, .Hooded
    case .Niko: model.build, model.snout_length, model.accessory, model.fur, model.pattern, scale = 1.08, 1.12, .Acorn_Cap, .Chestnut, .Pale_Belly, .94
    case .Iva: model.build, model.snout_length, model.accessory, model.fur, model.pattern, scale = .91, .86, .Flower, .Cream, .Piebald, 1.16
    case .Bojan: model.build, model.snout_length, model.accessory, model.fur, model.pattern, scale = 1.14, 1.22, .Bottle_Cap, .Soot, .Solid, .88
    case .Zora: model.build, model.snout_length, model.fur, model.pattern, scale = 1.18, 1.10, .Russet, .Piebald, 1.05
    case .Vesna: model.build, model.snout_length, model.accessory, model.fur, model.pattern, scale = .86, 1.08, .Chef_Hat, .White, .Pale_Belly, 1.02
    case .Petar: model.build, model.snout_length, model.fur, model.pattern, scale = 1.05, 1.18, .Russet, .Piebald, 1.10
    case .Anica: model.build, model.snout_length, model.accessory, model.fur, model.pattern, scale = .96, .82, .Goggles, .Chestnut, .Hooded, .90
    case .Toma: model.build, model.snout_length, model.accessory, model.fur, model.pattern = 1.06, .96, .Paper_Boat, .Chestnut, .Hooded
    case .Lena: model.build, model.snout_length, model.accessory, model.fur, model.pattern = .92, 1.10, .Paper_Boat, .Cream, .Piebald
    case .Mirna: model.build, model.snout_length, model.accessory, model.fur, model.pattern, scale = .98, .90, .Goggles, .Soot, .Piebald, 1.04
    }
    return model, scale
}

mouse_placement_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || !editor.mouse_placement_mode || editor.in_map || !cursor_hit do return
    if canvas2d.IsMouseButtonPressed(.RIGHT) {
        nearest, nearest_distance := -1, f32(2.5 * 2.5)
        for placement, index in editor.mouse_placements[:editor.mouse_placement_count] {
            dx, dz := placement.x - world_x, placement.z - world_z
            distance := dx * dx + dz * dz
            if distance < nearest_distance do nearest, nearest_distance = index, distance
        }
        if nearest >= 0 {
            structure_history_push_undo(editor)
            for index in nearest ..< editor.mouse_placement_count - 1 do editor.mouse_placements[index] = editor.mouse_placements[index + 1]
            editor.mouse_placement_count -= 1
            editor.mouse_placement_selected = 0
        }
        return
    }
    if !canvas2d.IsMouseButtonPressed(.LEFT) || editor.mouse_placement_count >= MOUSE_PLACEMENT_CAPACITY do return
    resident, available := mouse_placement_available_at(editor, editor.mouse_placement_selected)
    if !available do return
    structure_history_push_undo(editor)
    editor.mouse_placements[editor.mouse_placement_count] = {resident = resident, x = world_x, z = world_z, rotation = editor.mouse_placement_rotation}
    editor.mouse_placement_count += 1
    editor.mouse_placement_selected = 0
}

world_authored_mice :: proc(editor: ^Editor) {
    if editor == nil do return
    for placement in editor.mouse_placements[:editor.mouse_placement_count] {
        y := terrain.sample_surface_height(&editor.project, 0, placement.x, placement.z)
        model, scale := mouse_placement_profile(placement.resident, {placement.x, y, placement.z}, placement.rotation)
        world_mouse_model_scaled(editor, model, scale)
    }
}

when ODIN_TEST {
    @(test)
    mouse_placement_picker_excludes_placed_residents :: proc(t: ^testing.T) {
        editor := new(Editor, context.temp_allocator)
        editor.mouse_placements[0] = {resident = .Niko}
        editor.mouse_placement_count = 1
        testing.expect(t, mouse_placement_available_count(editor) == MOUSE_PLACEMENT_CAPACITY - 1)
        for index in 0 ..< mouse_placement_available_count(editor) {
            resident, ok := mouse_placement_available_at(editor, index)
            testing.expect(t, ok && resident != .Niko)
        }
    }
}
