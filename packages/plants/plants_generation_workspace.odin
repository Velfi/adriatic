package plants

import plant_structure "../plant_structure"

GENERATION_WORKSPACE_INITIAL_SEGMENTS :: 256
GENERATION_WORKSPACE_INITIAL_LEAVES :: 512
GENERATION_WORKSPACE_RETAINED_SEGMENTS_MAX :: 4_096
GENERATION_WORKSPACE_RETAINED_LEAVES_MAX :: 8_192

Generation_Workspace :: struct {
    segments: [dynamic]plant_structure.Segment,
    leaves:   [dynamic]plant_structure.Attachment_Anchor,
    borrowed: bool,
}

@(thread_local)
generation_thread_workspace: Generation_Workspace

@(thread_local)
generation_active_workspace: ^Generation_Workspace

@(thread_local)
generation_workspace_enabled_for_test: bool

generation_workspace_begin :: proc() -> bool {
    when ODIN_TEST {
        if !generation_workspace_enabled_for_test do return false
    }
    if generation_active_workspace != nil do return false
    generation_active_workspace = &generation_thread_workspace
    generation_active_workspace.borrowed = false
    return true
}

generation_workspace_end :: proc(started: bool) {
    if !started do return
    generation_active_workspace = nil
}

architecture_result_begin :: proc(result: ^plant_structure.Interpret_Result) {
    workspace := generation_active_workspace
    if result == nil || workspace == nil || workspace.borrowed do return
    clear(&workspace.segments)
    clear(&workspace.leaves)
    if cap(workspace.segments) < GENERATION_WORKSPACE_INITIAL_SEGMENTS {
        _ = non_zero_reserve(&workspace.segments, GENERATION_WORKSPACE_INITIAL_SEGMENTS)
    }
    if cap(workspace.leaves) < GENERATION_WORKSPACE_INITIAL_LEAVES {
        _ = non_zero_reserve(&workspace.leaves, GENERATION_WORKSPACE_INITIAL_LEAVES)
    }
    result.plant.segments = workspace.segments
    result.plant.leaves = workspace.leaves
    workspace.segments = nil
    workspace.leaves = nil
    workspace.borrowed = true
}

generation_workspace_dispose_interpreted :: proc(plant: ^plant_structure.Plant) {
    workspace := generation_active_workspace
    if plant == nil do return
    if workspace == nil || !workspace.borrowed {
        plant_structure.destroy_plant(plant)
        return
    }
    if cap(plant.segments) > GENERATION_WORKSPACE_RETAINED_SEGMENTS_MAX {
        delete(plant.segments)
    } else {
        clear(&plant.segments)
        workspace.segments = plant.segments
    }
    if cap(plant.leaves) > GENERATION_WORKSPACE_RETAINED_LEAVES_MAX {
        delete(plant.leaves)
    } else {
        clear(&plant.leaves)
        workspace.leaves = plant.leaves
    }
    plant^ = {}
    workspace.borrowed = false
}

generation_workspace_destroy_thread :: proc() {
    delete(generation_thread_workspace.segments)
    delete(generation_thread_workspace.leaves)
    generation_thread_workspace = {}
    if generation_active_workspace == &generation_thread_workspace do generation_active_workspace = nil
    generation_workspace_enabled_for_test = false
}
