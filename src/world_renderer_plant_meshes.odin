package main

world_plant_mesh_add :: proc(vertices: []Plant_Vertex, indices: []u32, casts_shadow: bool = true) -> int {
    if len(vertices) == 0 || len(indices) == 0 do return -1
    mesh := Plant_Instance_Mesh {
        first_vertex    = u32(len(world_renderer.plant_vertices)),
        vertex_capacity = u32(len(vertices)),
        first_index     = u32(len(world_renderer.instance_indices)),
        index_count     = u32(len(indices)),
        index_capacity  = u32(len(indices)),
        casts_shadow    = casts_shadow,
        instances       = make([dynamic]World_Mesh_Instance, 0, 64),
    }
    append(&world_renderer.plant_vertices, ..vertices)
    append(&world_renderer.instance_indices, ..indices)
    append(&world_renderer.plant_meshes, mesh)
    return len(world_renderer.plant_meshes) - 1
}

world_plant_mesh_release :: proc(mesh_index: int) {
    if mesh_index < 0 || mesh_index >= len(world_renderer.plant_meshes) do return
    mesh := &world_renderer.plant_meshes[mesh_index]
    clear(&mesh.instances)
    mesh.index_count = 0
    mesh.casts_shadow = false
    mesh.available = true
}

world_plant_mesh_reuse_or_add :: proc(vertices: []Plant_Vertex, indices: []u32, casts_shadow: bool = true) -> int {
    best := -1
    best_waste := ~u64(0)
    for &mesh, index in world_renderer.plant_meshes {
        if !mesh.available || len(vertices) > int(mesh.vertex_capacity) || len(indices) > int(mesh.index_capacity) do continue
        waste :=
            u64(mesh.vertex_capacity - u32(len(vertices))) * size_of(Plant_Vertex) +
            u64(mesh.index_capacity - u32(len(indices))) * size_of(u32)
        if waste < best_waste {
            best = index
            best_waste = waste
        }
    }
    if best >= 0 && world_plant_mesh_replace(best, vertices, indices, casts_shadow) do return best
    return world_plant_mesh_add(vertices, indices, casts_shadow)
}

world_plant_mesh_replace :: proc(
    mesh_index: int,
    vertices: []Plant_Vertex,
    indices: []u32,
    casts_shadow: bool = true,
) -> bool {
    if mesh_index < 0 || mesh_index >= len(world_renderer.plant_meshes) || len(vertices) == 0 || len(indices) == 0 do return false
    mesh := &world_renderer.plant_meshes[mesh_index]
    if len(vertices) > int(mesh.vertex_capacity) || len(indices) > int(mesh.index_capacity) do return false
    copy(world_renderer.plant_vertices[int(mesh.first_vertex):int(mesh.first_vertex) + len(vertices)], vertices)
    copy(world_renderer.instance_indices[int(mesh.first_index):int(mesh.first_index) + len(indices)], indices)
    mesh.index_count = u32(len(indices))
    mesh.casts_shadow = casts_shadow
    mesh.available = false
    clear(&mesh.instances)
    return true
}

world_plant_mesh_emit :: proc(mesh_index: int, instance: World_Mesh_Instance) {
    if mesh_index < 0 || mesh_index >= len(world_renderer.plant_meshes) do return
    if world_renderer.plant_meshes[mesh_index].available do return
    append(&world_renderer.plant_meshes[mesh_index].instances, instance)
}
