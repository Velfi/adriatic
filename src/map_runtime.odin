package main

import terrain "../packages/terrain"
import "core:crypto/sha2"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"

FIXTURE_MAP_SIDECAR_BASENAME_PREFIX :: "map-"
FIXTURE_MAP_SIDECAR_BASENAME_SUFFIX :: ".adriatic-map"
FIXTURE_MAP_SIDECAR_BASENAME_LENGTH ::
    len(FIXTURE_MAP_SIDECAR_BASENAME_PREFIX) + 2 * sha2.DIGEST_SIZE_256 + len(FIXTURE_MAP_SIDECAR_BASENAME_SUFFIX)

fixture_map_sidecar_hex_digit :: proc(value: byte) -> byte {
    if value < 10 do return '0' + value
    return 'a' + value - 10
}

fixture_map_sidecar_set_basename :: proc(sidecar: ^Fixture_Map_Sidecar) {
    if sidecar == nil do return
    sidecar.basename_count = FIXTURE_MAP_SIDECAR_BASENAME_LENGTH
    copy(sidecar.basename[:len(FIXTURE_MAP_SIDECAR_BASENAME_PREFIX)], FIXTURE_MAP_SIDECAR_BASENAME_PREFIX)
    offset := len(FIXTURE_MAP_SIDECAR_BASENAME_PREFIX)
    for value in sidecar.encoded_sha256 {
        sidecar.basename[offset] = fixture_map_sidecar_hex_digit(value >> 4)
        sidecar.basename[offset + 1] = fixture_map_sidecar_hex_digit(value & 0x0f)
        offset += 2
    }
    copy(
        sidecar.basename[offset:offset + len(FIXTURE_MAP_SIDECAR_BASENAME_SUFFIX)],
        FIXTURE_MAP_SIDECAR_BASENAME_SUFFIX,
    )
}

fixture_map_sidecar_canonical_basename :: proc(sidecar: Fixture_Map_Sidecar) -> bool {
    if sidecar.basename_count != FIXTURE_MAP_SIDECAR_BASENAME_LENGTH do return false
    expected := sidecar
    expected.basename = {}
    fixture_map_sidecar_set_basename(&expected)
    for index in 0 ..< FIXTURE_MAP_SIDECAR_BASENAME_LENGTH {
        if sidecar.basename[index] != expected.basename[index] do return false
    }
    for index in FIXTURE_MAP_SIDECAR_BASENAME_LENGTH ..< len(sidecar.basename) {
        if sidecar.basename[index] != 0 do return false
    }
    return true
}

fixture_map_sidecar_derive :: proc(encoded_adrmap: []byte) -> (Fixture_Map_Sidecar, bool) {
    if len(encoded_adrmap) == 0 do return {}, false
    format_version, generator_version, header_ok := map_artifact_header_version_pair(encoded_adrmap)
    _, supported := map_artifact_schema_pair(format_version, generator_version)
    if !header_ok || !supported do return {}, false
    sidecar := Fixture_Map_Sidecar {
        container_version = MAP_ARTIFACT_CONTAINER_VERSION,
        format_version    = format_version,
        generator_version = generator_version,
    }
    ctx: sha2.Context_256
    sha2.init_256(&ctx)
    sha2.update(&ctx, encoded_adrmap)
    sha2.final(&ctx, sidecar.encoded_sha256[:])
    fixture_map_sidecar_set_basename(&sidecar)
    return sidecar, true
}

fixture_map_sidecar_matches_encoded :: proc(sidecar: Fixture_Map_Sidecar, encoded_adrmap: []byte) -> bool {
    if !fixture_map_sidecar_valid(sidecar) || len(encoded_adrmap) == 0 do return false
    format_version, generator_version, header_ok := map_artifact_header_version_pair(encoded_adrmap)
    if !header_ok || format_version != sidecar.format_version || generator_version != sidecar.generator_version {
        return false
    }
    derived, derived_ok := fixture_map_sidecar_derive(encoded_adrmap)
    if !derived_ok do return false
    for index in 0 ..< len(sidecar.encoded_sha256) {
        if sidecar.encoded_sha256[index] != derived.encoded_sha256[index] do return false
    }
    return true
}

fixture_map_sidecar_resolve :: proc(
    fixture_path: string,
    sidecar: Fixture_Map_Sidecar,
    alloc := context.allocator,
) -> (
    string,
    bool,
) {
    if len(fixture_path) == 0 || !fixture_map_sidecar_valid(sidecar) || alloc.procedure == nil do return "", false
    local_sidecar := sidecar
    basename := string(local_sidecar.basename[:local_sidecar.basename_count])
    path, path_error := filepath.join([]string{os.dir(fixture_path), basename}, alloc)
    if path_error != nil || len(path) == 0 {
        if len(path) > 0 do delete(path, alloc)
        return "", false
    }
    return path, true
}

map_artifact_capture_fixture :: proc(
    fixture: ^Fixture,
    seeds := terrain.DEFAULT_ISLAND_SEEDS,
    alloc := context.allocator,
) -> (
    ^Map_Artifact,
    Map_Artifact_Error,
    bool,
) {
    if fixture == nil || alloc.procedure == nil do return nil, {kind = .Invalid_Argument}, false
    if fixture.project.structure_count < 0 || fixture.project.structure_count > len(fixture.project.structures) {
        return nil, {kind = .Invalid_State, message = "project structure count is invalid"}, false
    }
    artifact, allocated := map_artifact_allocate(alloc)
    if !allocated do return nil, map_artifact_allocation_error(), false
    artifact.generator_version = MAP_ARTIFACT_GENERATOR_VERSION
    artifact.seeds = seeds
    artifact.project = fixture.project
    artifact.river_water_splines = fixture.project.river_water_splines
    artifact.project.structures = nil
    artifact.project.terrain_pages = nil
    artifact.project.bathymetry_chunks = nil
    artifact.project.marine_habitat_chunks = nil
    artifact.project.terrain_page_lookup = nil
    artifact.project.bathymetry_chunk_lookup = nil
    artifact.project.marine_habitat_lookup = nil
    terrain.island_transforms_initialize(&artifact.project)
    if fixture.project.structure_count > 0 {
        structures, allocation_error := make([dynamic]terrain.Structure, fixture.project.structure_count, alloc)
        if allocation_error != nil {
            map_artifact_destroy(artifact, alloc)
            return nil, map_artifact_allocation_error(), false
        }
        copy(structures[:], fixture.project.structures[:fixture.project.structure_count])
        artifact.project.structures = structures
    }
    if len(fixture.project.terrain_pages) > 0 {
        pages, allocation_error := make([dynamic]terrain.Terrain_Page, len(fixture.project.terrain_pages), alloc)
        if allocation_error != nil {
            map_artifact_destroy(artifact, alloc)
            return nil, map_artifact_allocation_error(), false
        }
        copy(pages[:], fixture.project.terrain_pages[:])
        artifact.project.terrain_pages = pages
    }
    if len(fixture.project.bathymetry_chunks) > 0 {
        chunks, allocation_error := make(
            [dynamic]terrain.Bathymetry_Chunk,
            len(fixture.project.bathymetry_chunks),
            alloc,
        )
        if allocation_error != nil {
            map_artifact_destroy(artifact, alloc)
            return nil, map_artifact_allocation_error(), false
        }
        artifact.project.bathymetry_chunks = chunks
        for &source, index in fixture.project.bathymetry_chunks {
            target := &artifact.project.bathymetry_chunks[index]
            target^ = source
            target.heights = nil
            target.material = nil
            if len(source.heights) > 0 {
                heights, heights_error := make([dynamic]f16, len(source.heights), alloc)
                if heights_error != nil {
                    map_artifact_destroy(artifact, alloc)
                    return nil, map_artifact_allocation_error(), false
                }
                copy(heights[:], source.heights[:])
                target.heights = heights
            }
            if len(source.material) > 0 {
                material, material_error := make([dynamic]i8, len(source.material), alloc)
                if material_error != nil {
                    map_artifact_destroy(artifact, alloc)
                    return nil, map_artifact_allocation_error(), false
                }
                copy(material[:], source.material[:])
                target.material = material
            }
        }
    }
    if len(fixture.project.marine_habitat_chunks) > 0 {
        chunks, allocation_error := make(
            [dynamic]terrain.Marine_Habitat_Chunk,
            len(fixture.project.marine_habitat_chunks),
            alloc,
        )
        if allocation_error != nil {
            map_artifact_destroy(artifact, alloc)
            return nil, map_artifact_allocation_error(), false
        }
        artifact.project.marine_habitat_chunks = chunks
        for &source, index in fixture.project.marine_habitat_chunks {
            target := &artifact.project.marine_habitat_chunks[index]
            target^ = source
            target.cells = nil
            if len(source.cells) > 0 {
                cells, cells_error := make([dynamic]terrain.Marine_Habitat_Cell, len(source.cells), alloc)
                if cells_error != nil {
                    map_artifact_destroy(artifact, alloc)
                    return nil, map_artifact_allocation_error(), false
                }
                copy(cells[:], source.cells[:])
                target.cells = cells
            }
        }
    }
    artifact.settlement_plan = fixture.settlement_plan
    artifact.marina_authored = fixture.marina_authored
    artifact.marina_authored_plan = fixture.marina_authored_plan
    artifact.harbor_authored_plan = fixture.harbor_authored_plan
    artifact.harbor_authored_intervention = fixture.harbor_authored_intervention
    artifact.farms = fixture.farms
    artifact.farm_count = fixture.farm_count
    artifact.wrecks = fixture.wrecks
    artifact.wreck_count = fixture.wreck_count
    artifact.default_marinas = fixture.default_marinas
    artifact.default_harbors = fixture.default_harbors
    artifact.default_harbor_interventions = fixture.default_harbor_interventions
    artifact.default_marina_islands = fixture.default_marina_islands
    artifact.default_marina_count = fixture.default_marina_count
    artifact.greek_placements = fixture.greek_placements
    artifact.greek_placement_count = fixture.greek_placement_count
    return artifact, {}, true
}

map_artifact_capture :: proc(
    editor: ^Editor,
    seeds := terrain.DEFAULT_ISLAND_SEEDS,
    alloc := context.allocator,
) -> (
    ^Map_Artifact,
    Map_Artifact_Error,
    bool,
) {
    if editor == nil do return nil, {kind = .Invalid_Argument}, false
    return map_artifact_capture_fixture(&editor.fixture, seeds, alloc)
}

map_artifact_apply_fixture :: proc(fixture: ^Fixture, artifact: ^Map_Artifact) -> (Map_Artifact_Error, bool) {
    if fixture == nil || artifact == nil do return {kind = .Invalid_Argument}, false
    terrain.island_transforms_initialize(&artifact.project)
    if message, valid := map_artifact_valid(artifact); !valid {
        return {kind = .Invalid_State, message = message}, false
    }
    terrain.destroy_project(&fixture.project)
    fixture.project = artifact.project
    artifact.project.structures = nil
    artifact.project.terrain_pages = nil
    artifact.project.bathymetry_chunks = nil
    artifact.project.marine_habitat_chunks = nil
    artifact.project.terrain_page_lookup = nil
    artifact.project.bathymetry_chunk_lookup = nil
    artifact.project.marine_habitat_lookup = nil
    terrain.terrain_sampling_lookup_rebuild(&fixture.project)
    if len(fixture.project.marine_habitat_chunks) == 0 {
        terrain.marine_habitat_rebuild_all(&fixture.project)
    }
    fixture.project.river_water_splines = artifact.river_water_splines
    if fixture.project.river_water_splines[0].point_count == 0 ||
       fixture.project.river_water_splines[1].point_count == 0 {
        // Older artifacts excluded this derived state. Regenerate only while
        // loading those legacy maps; current baked maps restore it directly.
        terrain.rebuild_default_river_water_splines(&fixture.project, artifact.seeds)
    }
    fixture.settlement_plan = artifact.settlement_plan
    fixture.marina_authored = artifact.marina_authored
    fixture.marina_authored_plan = artifact.marina_authored_plan
    fixture.harbor_authored_plan = artifact.harbor_authored_plan
    fixture.harbor_authored_intervention = artifact.harbor_authored_intervention
    fixture.farms = artifact.farms
    fixture.farm_count = artifact.farm_count
    fixture.wrecks = artifact.wrecks
    fixture.wreck_count = artifact.wreck_count
    fixture.default_marinas = artifact.default_marinas
    fixture.default_harbors = artifact.default_harbors
    fixture.default_harbor_interventions = artifact.default_harbor_interventions
    fixture.default_marina_islands = artifact.default_marina_islands
    fixture.default_marina_count = artifact.default_marina_count
    fixture.default_map_regeneration_seeds = artifact.seeds
    fixture.greek_placements = artifact.greek_placements
    fixture.greek_placement_count = artifact.greek_placement_count
    return {}, true
}

fixture_map_sidecar_valid :: proc(sidecar: Fixture_Map_Sidecar) -> bool {
    if sidecar.container_version != MAP_ARTIFACT_CONTAINER_VERSION do return false
    _, supported := map_artifact_schema_pair(sidecar.format_version, sidecar.generator_version)
    if !supported do return false
    if !fixture_map_sidecar_canonical_basename(sidecar) do return false
    for value in sidecar.encoded_sha256 {
        if value != 0 do return true
    }
    return false
}

fixture_map_source_valid :: proc(source: Fixture_Map_Source) -> bool {
    switch source.kind {
    case .Inline:
        return len(source.inline_bytes) > 0 && source.sidecar == {}
    case .Sidecar:
        return len(source.inline_bytes) == 0 && fixture_map_sidecar_valid(source.sidecar)
    }
    return false
}

fixture_map_source_capture_inline :: proc(
    fixture: ^Fixture,
    alloc := context.allocator,
) -> (
    Fixture_Map_Source,
    Map_Artifact_Error,
    bool,
) {
    if fixture == nil || alloc.procedure == nil do return {}, {kind = .Invalid_Argument}, false
    seeds := fixture.default_map_regeneration_seeds
    defaults := terrain.DEFAULT_ISLAND_SEEDS
    for &seed, index in seeds do if seed == 0 do seed = defaults[index]
    artifact, capture_error, captured := map_artifact_capture_fixture(fixture, seeds, alloc)
    if !captured do return {}, capture_error, false
    defer map_artifact_destroy(artifact, alloc)
    encoded_bytes, encode_error, encoded := map_artifact_encode(artifact, alloc)
    if !encoded do return {}, encode_error, false
    defer delete(encoded_bytes, alloc)
    inline_bytes, allocation_error := make([dynamic]u8, len(encoded_bytes), alloc)
    if allocation_error != nil do return {}, map_artifact_allocation_error(), false
    copy(inline_bytes[:], encoded_bytes)
    return {kind = .Inline, inline_bytes = inline_bytes}, {}, true
}

fixture_map_source_clear_excluded :: proc(fixture: ^Fixture) {
    if fixture == nil do return
    fixture.project = {}
    fixture.marina_authored = false
    fixture.marina_authored_plan = {}
    fixture.harbor_authored_plan = {}
    fixture.harbor_authored_intervention = {}
    fixture.farms = {}
    fixture.farm_count = 0
    fixture.wrecks = {}
    fixture.wreck_count = 0
    fixture.default_marinas = {}
    fixture.default_harbors = {}
    fixture.default_harbor_interventions = {}
    fixture.default_marina_islands = {}
    fixture.default_marina_count = 0
    fixture.greek_placements = {}
    fixture.greek_placement_count = 0
    fixture.settlement_plan = {}
    fixture.default_map_regeneration_seeds = {}
}

fixture_map_source_apply_bytes :: proc(
    fixture: ^Fixture,
    encoded_adrmap: []byte,
    alloc := context.allocator,
) -> (
    Map_Artifact_Error,
    bool,
) {
    if fixture == nil || alloc.procedure == nil do return {kind = .Invalid_Argument}, false
    artifact, decode_error, decoded := map_artifact_decode(encoded_adrmap, alloc)
    if !decoded do return decode_error, false
    defer map_artifact_destroy(artifact, alloc)
    return map_artifact_apply_fixture(fixture, artifact)
}

fixture_map_source_apply_inline :: proc(fixture: ^Fixture, alloc := context.allocator) -> (Map_Artifact_Error, bool) {
    if fixture == nil || alloc.procedure == nil do return {kind = .Invalid_Argument}, false
    source := fixture.map_source
    if !fixture_map_source_valid(source) {
        return {kind = .Invalid_State, message = "map source is invalid"}, false
    }
    if source.kind == .Sidecar {
        return {kind = .Invalid_State, message = "map source sidecar requires a file resolver"}, false
    }
    return fixture_map_source_apply_bytes(fixture, source.inline_bytes[:], alloc)
}

fixture_map_source_apply_sidecar :: proc(
    fixture: ^Fixture,
    encoded_adrmap: []byte,
    alloc := context.allocator,
) -> (
    Map_Artifact_Error,
    bool,
) {
    if fixture == nil || alloc.procedure == nil do return {kind = .Invalid_Argument}, false
    source := fixture.map_source
    if !fixture_map_source_valid(source) || source.kind != .Sidecar {
        return {kind = .Invalid_State, message = "map source sidecar is invalid"}, false
    }
    if !fixture_map_sidecar_matches_encoded(source.sidecar, encoded_adrmap) {
        return {kind = .Invalid_State, message = "map source sidecar digest does not match"}, false
    }
    return fixture_map_source_apply_bytes(fixture, encoded_adrmap, alloc)
}

map_artifact_apply :: proc(editor: ^Editor, artifact: ^Map_Artifact) -> (Map_Artifact_Error, bool) {
    if editor == nil do return {kind = .Invalid_Argument}, false
    error, applied := map_artifact_apply_fixture(&editor.fixture, artifact)
    if !applied do return error, false
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

map_artifact_generation_progress :: proc(stage: string, current, total: int) {
    fmt.printf("map bake: %s %d/%d\n", stage, current, total)
}

map_artifact_generate :: proc(
    seeds := terrain.DEFAULT_ISLAND_SEEDS,
    alloc := context.allocator,
) -> (
    ^Map_Artifact,
    Map_Artifact_Error,
    bool,
) {
    editor := new(Editor, alloc)
    if editor == nil do return nil, {kind = .Limit_Exceeded}, false
    defer {
        structure_storage_destroy(editor)
        free(editor, alloc)
    }
    terrain.init_project_seeded(&editor.project, seeds, map_artifact_generation_progress)
    fmt.println("map bake: terrain complete")
    editor.terrain_revision = 1
    seed_default_island_marinas_seeded(editor, seeds)
    // Harbor generation may dredge or fill the seabed. Habitat is derived
    // only after those authoritative coastal edits have settled.
    marine_habitat_rebuild_world(editor)
    fmt.println("map bake: marinas complete")
    seed_default_island_towns_seeded(editor, seeds)
    fmt.println("map bake: towns complete")
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
    directory, directory_ok := map_artifact_save_directory(context.temp_allocator)
    path, path_ok := map_artifact_save_path(context.temp_allocator)
    if !directory_ok || !path_ok {
        fmt.eprintln("map save failed: could not resolve the user data path")
        terrain_file_feedback(editor, "MAP SAVE FAILED")
        return
    }
    if directory_error := os.make_directory_all(directory); directory_error != nil && directory_error != .Exist {
        fmt.eprintf("map save failed: could not create %s: %v\n", directory, directory_error)
        terrain_file_feedback(editor, "MAP SAVE FAILED")
        return
    }
    error, saved := map_editor_save_to_path(editor, path)
    defer map_artifact_error_dispose(&error)
    if saved {
        terrain_file_feedback(editor, "MAP SAVED")
    } else {
        fmt.eprintf("map save failed: %v %s %v\n", error.kind, error.message, error.os_error)
        terrain_file_feedback(editor, "MAP SAVE FAILED")
    }
}

map_editor_load :: proc(editor: ^Editor) {
    if editor == nil do return
    path, path_ok := map_artifact_save_path(context.temp_allocator)
    if !path_ok {
        fmt.eprintln("map load failed: could not resolve the user data path")
        terrain_file_feedback(editor, "MAP LOAD FAILED")
        return
    }
    error, loaded := map_editor_load_from_path(editor, path)
    defer map_artifact_error_dispose(&error)
    if loaded {
        terrain_file_feedback(editor, "MAP LOADED")
    } else {
        fmt.eprintf("map load failed: %v %s %v\n", error.kind, error.message, error.os_error)
        terrain_file_feedback(editor, "MAP LOAD FAILED")
    }
}
