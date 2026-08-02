package terrain

import "core:testing"
import "core:math"

@(test)
island_transform_round_trip :: proc(t: ^testing.T) {
    transform := Island_Transform{position_x = 120, position_z = -80, rotation = 0.7, uniform_scale = 1.5}
    world_x, world_z := island_local_to_world(transform, 34, -19)
    local_x, local_z := island_world_to_local(transform, world_x, world_z)
    testing.expect(t, math.abs(local_x - 34) < .0001)
    testing.expect(t, math.abs(local_z + 19) < .0001)
}

@(test)
island_chunk_sampling_is_transform_invariant :: proc(t: ^testing.T) {
    chunk := Island_Terrain_Chunk{key = {island_id = 7}, cell_size = 1, origin_x = -16, origin_z = -16}
    for index in 0 ..< ISLAND_CHUNK_SAMPLES {
        chunk.heights[index] = f16(index)
    }
    island := Island_Asset{
        id = 7,
        local_min_x = -16,
        local_min_z = -16,
        local_max_x = 16,
        local_max_z = 16,
        transform = {position_x = 500, position_z = 300, rotation = .5, uniform_scale = 1},
        chunks = make([dynamic]Island_Terrain_Chunk, 1),
    }
    island.chunks[0] = chunk
    world_x, world_z := island_local_to_world(island.transform, 0, 0)
    _, _, found := island_sample_world(&island, 0, world_x, world_z)
    testing.expect_value(t, found, true)
    delete(island.chunks)
}

@(test)
island_reposition_changes_only_transform :: proc(t: ^testing.T) {
    project := new(Project)
    defer free(project)
    project.revision = 10
    project.islands = make([dynamic]Island_Asset, 1)
    project.islands[0] = {id = 44, local_min_x = -10, local_min_z = -10, local_max_x = 10, local_max_z = 10, transform = {uniform_scale = 1}}
    before := project.islands[0]
    changed := project_set_island_transform(project, 44, {position_x = 90, position_z = -12, rotation = .25, uniform_scale = 1})
    testing.expect(t, changed)
    testing.expect_value(t, project.islands[0].id, before.id)
    testing.expect_value(t, project.islands[0].local_min_x, before.local_min_x)
    testing.expect_value(t, project.revision, u64(11))
    island_assets_destroy(&project.islands)
}
