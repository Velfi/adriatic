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

extern "C" uint32_t adriatic_optimize_unindexed_mesh(
    void *destination_vertices, uint32_t *destination_indices,
    const void *source_vertices, uint32_t vertex_count, uint32_t vertex_stride)
{
    if (!destination_vertices || !destination_indices || !source_vertices ||
        vertex_count == 0 || vertex_stride == 0 || vertex_count % 3 != 0)
        return 0;

    std::vector<unsigned int> remap(vertex_count);
    const size_t optimized_vertex_count = meshopt_generateVertexRemap(
        remap.data(), nullptr, vertex_count, source_vertices, vertex_count,
        vertex_stride);
    if (optimized_vertex_count == 0 || optimized_vertex_count > UINT32_MAX)
        return 0;

    std::vector<uint32_t> remapped_indices(vertex_count);
    std::vector<uint32_t> cache_indices(vertex_count);
    std::vector<uint8_t> remapped_vertices(optimized_vertex_count * vertex_stride);
    meshopt_remapIndexBuffer(
        remapped_indices.data(), nullptr, vertex_count, remap.data());
    meshopt_remapVertexBuffer(
        remapped_vertices.data(), source_vertices, vertex_count, vertex_stride,
        remap.data());
    meshopt_optimizeVertexCache(
        cache_indices.data(), remapped_indices.data(), vertex_count,
        optimized_vertex_count);
    std::memcpy(
        destination_indices, cache_indices.data(),
        vertex_count * sizeof(uint32_t));
    const size_t fetched_vertex_count = meshopt_optimizeVertexFetch(
        destination_vertices, destination_indices, vertex_count,
        remapped_vertices.data(), optimized_vertex_count, vertex_stride);
    return static_cast<uint32_t>(fetched_vertex_count);
}

extern "C" uint32_t adriatic_generate_optimized_mesh(
    const void *vertices, uint32_t vertex_count, uint32_t vertex_stride,
    uint32_t position_offset, uint32_t uv_offset, uint32_t part_offset,
    const uint16_t *indices, uint32_t triangle_count,
    float *uv_by_optimized_vertex, uint16_t *source_by_optimized_vertex,
    uint16_t *optimized_indices, uint32_t output_vertex_capacity,
    uint32_t output_index_capacity)
{
    if (!vertices || !indices || !uv_by_optimized_vertex || vertex_count == 0 ||
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

    const xatlas::Mesh &mesh = atlas->meshes[0];
    if (mesh.vertexCount > output_vertex_capacity ||
        mesh.indexCount != triangle_count * 3) {
        xatlas::Destroy(atlas);
        return 0;
    }

    // xatlas may split a source vertex at a chart seam. Keep its vertex and
    // index streams together; assigning one UV back to each source vertex and
    // then reusing the original indices loses that seam assignment.
    std::vector<uint8_t> keyed_vertices(
        static_cast<size_t>(mesh.vertexCount) * vertex_stride);
    std::vector<uint16_t> atlas_indices(mesh.indexCount);
    for (uint32_t index = 0; index < mesh.vertexCount; ++index) {
        const xatlas::Vertex &vertex = mesh.vertexArray[index];
        if (vertex.xref >= vertex_count || vertex.atlasIndex != 0) {
            xatlas::Destroy(atlas);
            return 0;
        }
        uint8_t *destination = keyed_vertices.data() +
            static_cast<size_t>(index) * vertex_stride;
        std::memcpy(
            destination,
            bytes + static_cast<size_t>(vertex.xref) * vertex_stride,
            vertex_stride);
        const float uv[2] = {
            vertex.uv[0] / float(atlas->width),
            vertex.uv[1] / float(atlas->height),
        };
        std::memcpy(destination + uv_offset, uv, sizeof(uv));
    }
    for (uint32_t index = 0; index < mesh.indexCount; ++index) {
        if (mesh.indexArray[index] >= mesh.vertexCount ||
            mesh.indexArray[index] > UINT16_MAX) {
            xatlas::Destroy(atlas);
            return 0;
        }
        atlas_indices[index] = static_cast<uint16_t>(mesh.indexArray[index]);
    }

    std::vector<unsigned int> remap(mesh.vertexCount);
    const size_t optimized_vertex_count = meshopt_generateVertexRemap(
        remap.data(), atlas_indices.data(), mesh.indexCount,
        keyed_vertices.data(), mesh.vertexCount, vertex_stride);
    if (optimized_vertex_count == 0 || optimized_vertex_count > output_vertex_capacity ||
        optimized_vertex_count > UINT16_MAX) {
        xatlas::Destroy(atlas);
        return 0;
    }

    std::vector<uint16_t> remapped_indices(triangle_count * 3);
    std::vector<uint16_t> cache_indices(triangle_count * 3);
    meshopt_remapIndexBuffer(
        remapped_indices.data(), atlas_indices.data(), triangle_count * 3,
        remap.data());
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

    std::vector<uint32_t> representative(optimized_vertex_count, UINT32_MAX);
    for (uint32_t atlas_vertex = 0; atlas_vertex < mesh.vertexCount; ++atlas_vertex) {
        if (representative[remap[atlas_vertex]] == UINT32_MAX)
            representative[remap[atlas_vertex]] = atlas_vertex;
    }
    for (uint32_t old_index = 0; old_index < optimized_vertex_count; ++old_index) {
        const uint32_t atlas_vertex = representative[old_index];
        if (atlas_vertex == UINT32_MAX) {
            xatlas::Destroy(atlas);
            return 0;
        }
        const uint32_t optimized_index = fetch_remap[old_index];
        const xatlas::Vertex &vertex = mesh.vertexArray[atlas_vertex];
        source_by_optimized_vertex[optimized_index] =
            static_cast<uint16_t>(vertex.xref);
        uv_by_optimized_vertex[optimized_index * 2] =
            vertex.uv[0] / float(atlas->width);
        uv_by_optimized_vertex[optimized_index * 2 + 1] =
            vertex.uv[1] / float(atlas->height);
    }

    xatlas::Destroy(atlas);
    return static_cast<uint32_t>(optimized_vertex_count);
}

extern "C" uint32_t adriatic_generate_uv_atlas(
    const float *positions, uint32_t vertex_count, const uint32_t *indices,
    uint32_t index_count, uint32_t *source_by_atlas_vertex,
    float *uv_by_atlas_vertex, uint32_t *atlas_indices,
    uint32_t output_vertex_capacity)
{
    if (!positions || !indices || !source_by_atlas_vertex ||
        !uv_by_atlas_vertex || !atlas_indices || vertex_count == 0 ||
        index_count == 0 || index_count % 3 != 0) return 0;

    xatlas::Atlas *atlas = xatlas::Create();
    if (!atlas) return 0;
    xatlas::MeshDecl declaration;
    declaration.vertexPositionData = positions;
    declaration.vertexCount = vertex_count;
    declaration.vertexPositionStride = sizeof(float) * 3;
    declaration.indexData = indices;
    declaration.indexCount = index_count;
    declaration.indexFormat = xatlas::IndexFormat::UInt32;
    if (xatlas::AddMesh(atlas, declaration) != xatlas::AddMeshError::Success) {
        xatlas::Destroy(atlas);
        return 0;
    }

    xatlas::ChartOptions chart_options;
    xatlas::PackOptions pack_options;
    pack_options.padding = 2;
    pack_options.resolution = 512;
    xatlas::Generate(atlas, chart_options, pack_options);
    if (atlas->meshCount != 1 || atlas->width == 0 || atlas->height == 0) {
        xatlas::Destroy(atlas);
        return 0;
    }
    const xatlas::Mesh &mesh = atlas->meshes[0];
    if (mesh.vertexCount > output_vertex_capacity || mesh.indexCount != index_count) {
        xatlas::Destroy(atlas);
        return 0;
    }
    for (uint32_t vertex_index = 0; vertex_index < mesh.vertexCount; ++vertex_index) {
        const xatlas::Vertex &vertex = mesh.vertexArray[vertex_index];
        if (vertex.xref >= vertex_count || vertex.atlasIndex != 0) {
            xatlas::Destroy(atlas);
            return 0;
        }
        source_by_atlas_vertex[vertex_index] = vertex.xref;
        uv_by_atlas_vertex[vertex_index * 2] = vertex.uv[0] / float(atlas->width);
        uv_by_atlas_vertex[vertex_index * 2 + 1] = vertex.uv[1] / float(atlas->height);
    }
    std::memcpy(atlas_indices, mesh.indexArray, sizeof(uint32_t) * index_count);
    const uint32_t result = mesh.vertexCount;
    xatlas::Destroy(atlas);
    return result;
}
