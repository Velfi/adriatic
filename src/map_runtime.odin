package main

import terrain "../packages/terrain"
import "core:fmt"
import "core:mem"

map_artifact_capture :: proc(
    editor: ^Editor,
    seeds := terrain.DEFAULT_ISLAND_SEEDS,
    alloc := context.allocator,
) -> (^Map_Artifact, Map_Artifact_Error, bool) {
    if editor == nil || alloc.procedure == nil do return nil, {kind = .Invalid_Argument}, false
    artifact := new(Map_Artifact, alloc)
    if artifact == nil do return nil, {kind = .Limit_Exceeded}, false
    artifact.generator_version = MAP_ARTIFACT_GENERATOR_VERSION
    artifact.seeds = seeds
    artifact.project = editor.project
    artifact.project.structures = nil
    if editor.project.structure_count > 0 {
        structures, allocation_error := make([dynamic]terrain.Structure, editor.project.structure_count, alloc)
        if allocation_error != nil {
            map_artifact_destroy(artifact, alloc)
            return nil, {kind = .Limit_Exceeded}, false
        }
        copy(structures[:], editor.project.structures[:editor.project.structure_count])
        artifact.project.structures = structures
    }
    artifact.settlement_plan = editor.settlement_plan
    artifact.marina_authored = editor.marina_authored
    artifact.marina_authored_plan = editor.marina_authored_plan
    artifact.harbor_authored_plan = editor.harbor_authored_plan
    artifact.harbor_authored_intervention = editor.harbor_authored_intervention
    artifact.farms = editor.farms
    artifact.farm_count = editor.farm_count
    artifact.wrecks = editor.wrecks
    artifact.wreck_count = editor.wreck_count
    artifact.default_marinas = editor.default_marinas
    artifact.default_harbors = editor.default_harbors
    artifact.default_harbor_interventions = editor.default_harbor_interventions
    artifact.default_marina_islands = editor.default_marina_islands
    artifact.default_marina_count = editor.default_marina_count
    artifact.greek_placements = editor.greek_placements
    artifact.greek_placement_count = editor.greek_placement_count
    return artifact, {}, true
}

map_artifact_apply :: proc(editor: ^Editor, artifact: ^Map_Artifact) -> (Map_Artifact_Error, bool) {
    if editor == nil || artifact == nil do return {kind = .Invalid_Argument}, false
    if message, valid := map_artifact_valid(artifact); !valid {
        return {kind = .Invalid_State, message = message}, false
    }
    terrain.destroy_project(&editor.project)
    editor.project = artifact.project
    artifact.project.structures = nil
    editor.settlement_plan = artifact.settlement_plan
    editor.marina_authored = artifact.marina_authored
    editor.marina_authored_plan = artifact.marina_authored_plan
    editor.harbor_authored_plan = artifact.harbor_authored_plan
    editor.harbor_authored_intervention = artifact.harbor_authored_intervention
    editor.farms = artifact.farms
    editor.farm_count = artifact.farm_count
    editor.wrecks = artifact.wrecks
    editor.wreck_count = artifact.wreck_count
    editor.default_marinas = artifact.default_marinas
    editor.default_harbors = artifact.default_harbors
    editor.default_harbor_interventions = artifact.default_harbor_interventions
    editor.default_marina_islands = artifact.default_marina_islands
    editor.default_marina_count = artifact.default_marina_count
    editor.greek_placements = artifact.greek_placements
    editor.greek_placement_count = artifact.greek_placement_count
    editor.default_map_regeneration_seeds = artifact.seeds
    editor.terrain_revision += 1
    if editor.terrain_revision == 0 do editor.terrain_revision = 1
    editor.project.revision = max(editor.project.revision, u64(1))
    editor.terrain_saved_revision = editor.project.revision
    editor.structure_selected = -1
    editor.road_selected_node = -1
    editor.structure_undo_count = 0
    editor.structure_redo_count = 0
    editor.terrain_undo_count = 0
    editor.terrain_redo_count = 0
    editor.circulation_plan_valid = false
    editor.circulation_revision = 0
    return {}, true
}

map_artifact_generate :: proc(
    seeds := terrain.DEFAULT_ISLAND_SEEDS,
    alloc := context.allocator,
) -> (^Map_Artifact, Map_Artifact_Error, bool) {
    editor := new(Editor, alloc)
    if editor == nil do return nil, {kind = .Limit_Exceeded}, false
    defer {
        structure_storage_destroy(editor)
        free(editor, alloc)
    }
    terrain.init_project_seeded(&editor.project, seeds)
    editor.terrain_revision = 1
    seed_default_island_marinas_seeded(editor, seeds)
    seed_default_island_towns_seeded(editor, seeds)
    return map_artifact_capture(editor, seeds, alloc)
}

map_editor_save_to_path :: proc(editor: ^Editor, path: string) -> (Map_Artifact_Error, bool) {
    seeds := editor.default_map_regeneration_seeds
    defaults := terrain.DEFAULT_ISLAND_SEEDS
    for &seed, index in seeds do if seed == 0 do seed = defaults[index]
    artifact, capture_error, captured := map_artifact_capture(editor, seeds)
    if !captured do return capture_error, false
    defer map_artifact_destroy(artifact)
    return map_artifact_write(artifact, path)
}

map_editor_load_from_path :: proc(editor: ^Editor, path: string) -> (Map_Artifact_Error, bool) {
    artifact, read_error, read_ok := map_artifact_read(path)
    if !read_ok do return read_error, false
    defer map_artifact_destroy(artifact)
    apply_error, applied := map_artifact_apply(editor, artifact)
    if !applied do return apply_error, false
    world_terrain_invalidate_all(editor)
    gameplay_physics_rebuild_structures(editor)
    return {}, true
}

map_editor_save :: proc(editor: ^Editor) {
    if editor == nil do return
    error, saved := map_editor_save_to_path(editor, EDITOR_MAP_ARTIFACT_PATH)
    defer map_artifact_error_dispose(&error)
    if saved {
        terrain_file_feedback(editor, "MAP SAVED")
    } else {
        fmt.eprintf("map save failed: %v %s\n", error.kind, error.message)
        terrain_file_feedback(editor, "MAP SAVE FAILED")
    }
}

map_editor_load :: proc(editor: ^Editor) {
    if editor == nil do return
    error, loaded := map_editor_load_from_path(editor, EDITOR_MAP_ARTIFACT_PATH)
    defer map_artifact_error_dispose(&error)
    if loaded {
        terrain_file_feedback(editor, "MAP LOADED")
    } else {
        fmt.eprintf("map load failed: %v %s\n", error.kind, error.message)
        terrain_file_feedback(editor, "MAP LOAD FAILED")
    }
}
