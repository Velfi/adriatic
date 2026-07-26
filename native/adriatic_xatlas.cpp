#include "../third_party/xatlas/source/xatlas/xatlas.h"
#include "../third_party/meshoptimizer/src/meshoptimizer.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

extern "C" void adriatic_optimize_index_buffer(
    uint16_t *destination, const uint16_t *indices, uint32_t index_count,
    uint32_t vertex_count)
{
    if (!destination || !indices || index_count == 0 || vertex_count == 0) return;
    meshopt_optimizeVertexCache(destination, indices, index_count, vertex_count);
}

extern "C" uint32_t adriatic_generate_optimized_mesh(
    const void *vertices, uint32_t vertex_count, uint32_t vertex_stride,
    uint32_t position_offset, uint32_t uv_offset, uint32_t part_offset,
    const uint16_t *indices, uint32_t triangle_count,
    float *uv_by_source_vertex, uint16_t *source_by_optimized_vertex,
    uint16_t *optimized_indices, uint32_t output_vertex_capacity,
    uint32_t output_index_capacity)
{
    if (!vertices || !indices || !uv_by_source_vertex || vertex_count == 0 ||
        !source_by_optimized_vertex || !optimized_indices || triangle_count == 0 ||
        output_vertex_capacity < vertex_count ||
        output_index_capacity < triangle_count * 3) return 0;

    const auto *bytes = static_cast<const uint8_t *>(vertices);
    std::vector<uint32_t> materials(triangle_count);
    for (uint32_t face = 0; face < triangle_count; ++face) {
        const uint16_t source = indices[face * 3];
        materials[face] = bytes[static_cast<size_t>(source) * vertex_stride + part_offset];
    }

    xatlas::Atlas *atlas = xatlas::Create();
    if (!atlas) return 0;
    xatlas::MeshDecl declaration;
    declaration.vertexPositionData = bytes + position_offset;
    declaration.vertexCount = vertex_count;
    declaration.vertexPositionStride = vertex_stride;
    declaration.indexData = indices;
    declaration.indexCount = triangle_count * 3;
    declaration.indexFormat = xatlas::IndexFormat::UInt16;
    declaration.faceMaterialData = materials.data();
    if (xatlas::AddMesh(atlas, declaration) != xatlas::AddMeshError::Success) {
        xatlas::Destroy(atlas);
        return 0;
    }

    xatlas::ChartOptions chart_options;
    xatlas::PackOptions pack_options;
    pack_options.padding = 4;
    pack_options.resolution = 1024;
    xatlas::Generate(atlas, chart_options, pack_options);
    if (atlas->meshCount != 1 || atlas->width == 0 || atlas->height == 0) {
        xatlas::Destroy(atlas);
        return 0;
    }

    std::vector<uint8_t> assigned(vertex_count, 0);
    const xatlas::Mesh &mesh = atlas->meshes[0];
    for (uint32_t index = 0; index < mesh.vertexCount; ++index) {
        const xatlas::Vertex &vertex = mesh.vertexArray[index];
        if (vertex.xref >= vertex_count || vertex.atlasIndex != 0) continue;
        uv_by_source_vertex[vertex.xref * 2] = vertex.uv[0] / float(atlas->width);
        uv_by_source_vertex[vertex.xref * 2 + 1] = vertex.uv[1] / float(atlas->height);
        assigned[vertex.xref] = 1;
    }
    for (uint32_t index = 0; index < vertex_count; ++index) {
        if (!assigned[index]) {
            xatlas::Destroy(atlas);
            return 0;
        }
    }
    xatlas::Destroy(atlas);

    // Include the generated UVs and Adriatic's part/animation metadata in the
    // vertex key. UV seams and independently animated assemblies must remain
    // split even when their positions happen to coincide.
    std::vector<uint8_t> keyed_vertices(static_cast<size_t>(vertex_count) * vertex_stride);
    std::memcpy(keyed_vertices.data(), vertices, keyed_vertices.size());
    for (uint32_t index = 0; index < vertex_count; ++index) {
        std::memcpy(
            keyed_vertices.data() + static_cast<size_t>(index) * vertex_stride + uv_offset,
            uv_by_source_vertex + index * 2,
            sizeof(float) * 2);
    }

    std::vector<unsigned int> remap(vertex_count);
    const size_t optimized_vertex_count = meshopt_generateVertexRemap(
        remap.data(), indices, triangle_count * 3, keyed_vertices.data(),
        vertex_count, vertex_stride);
    if (optimized_vertex_count == 0 || optimized_vertex_count > output_vertex_capacity ||
        optimized_vertex_count > UINT16_MAX) return 0;

    std::vector<uint16_t> remapped_indices(triangle_count * 3);
    std::vector<uint16_t> cache_indices(triangle_count * 3);
    meshopt_remapIndexBuffer(
        remapped_indices.data(), indices, triangle_count * 3, remap.data());
    meshopt_optimizeVertexCache(
        cache_indices.data(), remapped_indices.data(), triangle_count * 3,
        optimized_vertex_count);

    std::vector<unsigned int> fetch_remap(optimized_vertex_count);
    meshopt_optimizeVertexFetchRemap(
        fetch_remap.data(), cache_indices.data(), triangle_count * 3,
        optimized_vertex_count);
    meshopt_remapIndexBuffer(
        optimized_indices, cache_indices.data(), triangle_count * 3,
        fetch_remap.data());

    std::vector<uint16_t> representative(optimized_vertex_count, UINT16_MAX);
    for (uint32_t source = 0; source < vertex_count; ++source) {
        if (representative[remap[source]] == UINT16_MAX)
            representative[remap[source]] = static_cast<uint16_t>(source);
    }
    for (uint32_t old_index = 0; old_index < optimized_vertex_count; ++old_index)
        source_by_optimized_vertex[fetch_remap[old_index]] = representative[old_index];

    return static_cast<uint32_t>(optimized_vertex_count);
}
