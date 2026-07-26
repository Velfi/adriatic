package vehicles

import "core:sync"

foreign import adriatic_mesh "system:adriatic_mesh"

foreign adriatic_mesh {
    adriatic_generate_optimized_mesh :: proc(vertices: rawptr, vertex_count, vertex_stride, position_offset, uv_offset, part_offset: u32, indices: ^u16, triangle_count: u32, uv_by_source_vertex: ^f32, source_by_optimized_vertex, optimized_indices: ^u16, output_vertex_capacity, output_index_capacity: u32) -> u32 ---
}

Mesh_Optimization_Cache :: struct {
    source_vertex_count:    int,
    optimized_vertex_count: int,
    ready:                  bool,
}

mesh_optimization_lock: sync.Mutex
postale_mesh_cache: Mesh_Optimization_Cache
pelican_mesh_cache: Mesh_Optimization_Cache
libellula_mesh_cache: Mesh_Optimization_Cache
libellula_mk2_mesh_cache: Mesh_Optimization_Cache

postale_uvs: [AIRCRAFT_MESH_VERTEX_CAPACITY * 2]f32
postale_sources: [AIRCRAFT_MESH_VERTEX_CAPACITY]u16
postale_indices: [AIRCRAFT_MESH_TRIANGLE_CAPACITY * 3]u16
postale_scratch: [AIRCRAFT_MESH_VERTEX_CAPACITY]Mesh_Vertex
pelican_uvs: [AIRCRAFT_MESH_VERTEX_CAPACITY * 2]f32
pelican_sources: [AIRCRAFT_MESH_VERTEX_CAPACITY]u16
pelican_indices: [AIRCRAFT_MESH_TRIANGLE_CAPACITY * 3]u16
pelican_scratch: [AIRCRAFT_MESH_VERTEX_CAPACITY]Mesh_Vertex

libellula_uvs: [LIBELLULA_MESH_VERTEX_CAPACITY * 2]f32
libellula_sources: [LIBELLULA_MESH_VERTEX_CAPACITY]u16
libellula_indices: [LIBELLULA_MESH_TRIANGLE_CAPACITY * 3]u16
libellula_scratch: [LIBELLULA_MESH_VERTEX_CAPACITY]Mesh_Vertex
libellula_mk2_uvs: [LIBELLULA_MESH_VERTEX_CAPACITY * 2]f32
libellula_mk2_sources: [LIBELLULA_MESH_VERTEX_CAPACITY]u16
libellula_mk2_indices: [LIBELLULA_MESH_TRIANGLE_CAPACITY * 3]u16
libellula_mk2_scratch: [LIBELLULA_MESH_VERTEX_CAPACITY]Mesh_Vertex

mesh_finalize :: proc(
    mesh: ^$Mesh,
    cache: ^Mesh_Optimization_Cache,
    uvs: []f32,
    sources, optimized_indices: []u16,
    scratch: []Mesh_Vertex,
) {
    if mesh == nil || cache == nil || mesh.vertex_count <= 0 do return
    sync.mutex_lock(&mesh_optimization_lock)
    defer sync.mutex_unlock(&mesh_optimization_lock)

    source_vertex_count := mesh.vertex_count
    if !cache.ready || cache.source_vertex_count != source_vertex_count {
        cache.source_vertex_count = source_vertex_count
        cache.optimized_vertex_count = int(
            adriatic_generate_optimized_mesh(
                rawptr(&mesh.vertices[0]),
                u32(source_vertex_count),
                u32(size_of(Mesh_Vertex)),
                u32(offset_of(Mesh_Vertex, position)),
                u32(offset_of(Mesh_Vertex, uv)),
                u32(offset_of(Mesh_Vertex, part)),
                &mesh.triangles[0].a,
                u32(mesh.triangle_count),
                raw_data(uvs),
                raw_data(sources),
                raw_data(optimized_indices),
                u32(len(sources)),
                u32(len(optimized_indices)),
            ),
        )
        cache.ready = cache.optimized_vertex_count > 0
    }
    if !cache.ready do return

    for optimized_index in 0 ..< cache.optimized_vertex_count {
        source_index := int(sources[optimized_index])
        scratch[optimized_index] = mesh.vertices[source_index]
        scratch[optimized_index].uv = {uvs[source_index * 2], uvs[source_index * 2 + 1]}
    }
    copy(mesh.vertices[:cache.optimized_vertex_count], scratch[:cache.optimized_vertex_count])
    for triangle_index in 0 ..< mesh.triangle_count {
        mesh.triangles[triangle_index] = {
            optimized_indices[triangle_index * 3],
            optimized_indices[triangle_index * 3 + 1],
            optimized_indices[triangle_index * 3 + 2],
        }
    }
    mesh.vertex_count = cache.optimized_vertex_count
}
