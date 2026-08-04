package terrain

import "core:testing"

marine_habitat_test_project :: proc() -> ^Project {
    project := new(Project)
    project.sea_level = 0
    project.island_transforms = default_island_transforms()
    bed := Bathymetry_Chunk {
        owner    = .World,
        revision = 4,
        heights  = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    for &height in bed.heights do height = -5
    for &material in bed.material do material = -48
    append(&project.bathymetry_chunks, bed)
    terrain_sampling_lookup_rebuild(project)
    return project
}

@(test)
marine_habitat_bakes_and_samples_seagrass :: proc(t: ^testing.T) {
    project := marine_habitat_test_project()
    defer free_project(project)
    marine_habitat_rebuild_all(project)
    sample, found := sample_marine_habitat(project, 24, 24)
    testing.expect(t, found)
    testing.expect(t, sample.seagrass > sample.macroalgae)
    testing.expect_value(t, marine_habitat_dominant(sample), Marine_Habitat_Kind.Seagrass)
}

@(test)
marine_habitat_disturbance_clears_and_restores :: proc(t: ^testing.T) {
    project := marine_habitat_test_project()
    defer free_project(project)
    exclusion := [1]Marine_Habitat_Exclusion{{center_x = 24, center_z = 24, radius = 18}}
    marine_habitat_rebuild_all(project, exclusion[:])
    disturbed, found := sample_marine_habitat(project, 24, 24)
    testing.expect(t, found)
    testing.expect(t, disturbed.disturbance > .95 && disturbed.seagrass < .01)
    marine_habitat_rebuild_all(project)
    restored, restored_found := sample_marine_habitat(project, 24, 24)
    testing.expect(t, restored_found)
    testing.expect(t, restored.disturbance < .01 && restored.seagrass > .1)
}

@(test)
marine_habitat_rejects_stale_bathymetry_revision :: proc(t: ^testing.T) {
    project := marine_habitat_test_project()
    defer free_project(project)
    marine_habitat_rebuild_all(project)
    project.bathymetry_chunks[0].revision += 1
    _, found := sample_marine_habitat(project, 24, 24)
    testing.expect(t, !found)
}

@(test)
marine_habitat_is_deterministic :: proc(t: ^testing.T) {
    project := marine_habitat_test_project()
    defer free_project(project)
    marine_habitat_rebuild_all(project)
    first := project.marine_habitat_chunks[0].cells[17]
    marine_habitat_rebuild_all(project)
    testing.expect_value(t, project.marine_habitat_chunks[0].cells[17], first)
}

@(test)
marine_habitat_is_released_when_project_is_reinitialized :: proc(t: ^testing.T) {
    project := marine_habitat_test_project()
    defer free_project(project)
    marine_habitat_rebuild_all(project)
    testing.expect(t, len(project.marine_habitat_chunks) > 0)
    testing.expect(t, len(project.marine_habitat_lookup) > 0)

    init_project(project)

    testing.expect_value(t, len(project.marine_habitat_chunks), 0)
    testing.expect_value(t, len(project.marine_habitat_lookup), 0)
}

@(test)
marine_habitat_paint_changes_only_the_selected_ecology :: proc(t: ^testing.T) {
    project := marine_habitat_test_project()
    defer free_project(project)
    marine_habitat_rebuild_all(project)
    before, found := sample_marine_habitat(project, 24, 24)
    testing.expect(t, found)
    changed := marine_habitat_paint(project, 24, 24, 20, 1, 1, .Coralligenous)
    after, after_found := sample_marine_habitat(project, 24, 24)
    testing.expect(t, changed && after_found)
    testing.expect(t, after.coralligenous > before.coralligenous)
    testing.expect(t, project.marine_habitat_chunks[0].revision > 1)
}

@(test)
marine_habitat_bare_paint_clears_life_and_is_erasable :: proc(t: ^testing.T) {
    project := marine_habitat_test_project()
    defer free_project(project)
    marine_habitat_rebuild_all(project)
    before, _ := sample_marine_habitat(project, 24, 24)
    testing.expect(t, marine_habitat_paint(project, 24, 24, 20, 1, 1, .Bare))
    bare, _ := sample_marine_habitat(project, 24, 24)
    testing.expect(t, bare.disturbance > before.disturbance)
    testing.expect(t, bare.seagrass < before.seagrass)
    testing.expect(t, marine_habitat_paint(project, 24, 24, 20, 1, 1, .Bare, true))
    restored, _ := sample_marine_habitat(project, 24, 24)
    testing.expect(t, restored.disturbance < bare.disturbance)
}
