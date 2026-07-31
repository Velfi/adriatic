package main

import vehicles "../packages/vehicles"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"

VEHICLE_MESH_CACHE_MAGIC :: [8]u8{'A', 'D', 'R', 'M', 'E', 'S', 'H', 0}
VEHICLE_MESH_CACHE_VERSION :: u32(1)
POSTALE_MESH_CACHE_VERSION :: u32(1)
CAR_MESH_CACHE_VERSION :: u32(1)

Vehicle_Mesh_Cache_Header :: struct {
    magic:          [8]u8,
    version:        u32,
    vertex_stride:  u32,
    triangle_stride:u32,
    vertex_count:   u32,
    triangle_count: u32,
    payload_size:   u64,
    checksum:       u64,
}

vehicle_mesh_cache_path :: proc(allocator := context.allocator) -> (string, bool) {
    base, base_error := os.user_data_dir(allocator)
    if base_error != nil || base == "" do return "", false
    path, path_error := strings.concatenate({base, "/Adriatic/cache/libellula-mk2-v1.mesh"}, allocator)
    return path, path_error == nil
}

aircraft_mesh_cache_path :: proc(name: string, version: u32, allocator := context.allocator) -> (string, bool) {
    base, base_error := os.user_data_dir(allocator)
    if base_error != nil || base == "" do return "", false
    path, path_error := strings.concatenate(
        {base, "/Adriatic/cache/", name, "-v", fmt.tprintf("%d", version), ".mesh"},
        allocator,
    )
    return path, path_error == nil
}

vehicle_mesh_cache_directory :: proc(allocator := context.allocator) -> (string, bool) {
    base, base_error := os.user_data_dir(allocator)
    if base_error != nil || base == "" do return "", false
    path, path_error := strings.concatenate({base, "/Adriatic/cache"}, allocator)
    return path, path_error == nil
}

vehicle_mesh_cache_payload :: proc(mesh: ^vehicles.Libellula_Mesh) -> (vertices, triangles: []u8) {
    if mesh == nil || mesh.vertex_count <= 0 || mesh.triangle_count <= 0 do return
    vertices = mem.slice_ptr(cast([^]u8)raw_data(mesh.vertices), mesh.vertex_count * size_of(vehicles.Mesh_Vertex))
    triangles = mem.slice_ptr(cast([^]u8)raw_data(mesh.triangles), mesh.triangle_count * size_of(vehicles.Mesh_Triangle))
    return
}

vehicle_mesh_cache_checksum :: proc(vertices, triangles: []u8) -> u64 {
    value: u64 = 14695981039346656037
    for item in vertices do value = (value ~ u64(item)) * 1099511628211
    for item in triangles do value = (value ~ u64(item)) * 1099511628211
    return value
}

vehicle_mesh_cache_load :: proc(mesh: ^vehicles.Libellula_Mesh, path: string) -> bool {
    if mesh == nil || mesh.vertices == nil || mesh.triangles == nil || path == "" do return false
    data, read_error := os.read_entire_file(path, context.temp_allocator)
    if read_error != nil || len(data) < size_of(Vehicle_Mesh_Cache_Header) do return false
    header := cast(^Vehicle_Mesh_Cache_Header)raw_data(data)
    if header.magic != VEHICLE_MESH_CACHE_MAGIC ||
       header.version != VEHICLE_MESH_CACHE_VERSION ||
       header.vertex_stride != u32(size_of(vehicles.Mesh_Vertex)) ||
       header.triangle_stride != u32(size_of(vehicles.Mesh_Triangle)) ||
       header.vertex_count == 0 || int(header.vertex_count) > len(mesh.vertices) ||
       header.triangle_count == 0 || int(header.triangle_count) > len(mesh.triangles) {
        return false
    }
    vertex_size := int(header.vertex_count) * size_of(vehicles.Mesh_Vertex)
    triangle_size := int(header.triangle_count) * size_of(vehicles.Mesh_Triangle)
    if header.payload_size != u64(vertex_size + triangle_size) ||
       len(data) != size_of(Vehicle_Mesh_Cache_Header) + vertex_size + triangle_size {
        return false
    }
    payload := data[size_of(Vehicle_Mesh_Cache_Header):]
    vertex_bytes := payload[:vertex_size]
    triangle_bytes := payload[vertex_size:]
    if hash.fnv64a(payload) != header.checksum do return false

    cached_vertices := mem.slice_ptr(cast([^]vehicles.Mesh_Vertex)raw_data(vertex_bytes), int(header.vertex_count))
    cached_triangles := mem.slice_ptr(cast([^]vehicles.Mesh_Triangle)raw_data(triangle_bytes), int(header.triangle_count))
    for vertex in cached_vertices {
        for component in vertex.position {
            if math.is_nan(component) || math.is_inf(component, 0) do return false
        }
        for component in vertex.normal {
            if math.is_nan(component) || math.is_inf(component, 0) do return false
        }
        for component in vertex.uv {
            if math.is_nan(component) || math.is_inf(component, 0) do return false
        }
        if int(vertex.part) > int(vehicles.Aircraft_Mesh_Part.Lift_Frame) ||
           int(vertex.animation_group) > int(vehicles.Mesh_Animation_Group.Libellula_Mk2_Rear_Rotor) {
            return false
        }
    }
    for triangle in cached_triangles {
        if u32(triangle.a) >= header.vertex_count ||
           u32(triangle.b) >= header.vertex_count ||
           u32(triangle.c) >= header.vertex_count {
            return false
        }
    }
    copy(mesh.vertices[:int(header.vertex_count)], cached_vertices)
    copy(mesh.triangles[:int(header.triangle_count)], cached_triangles)
    mesh.vertex_count = int(header.vertex_count)
    mesh.triangle_count = int(header.triangle_count)
    return true
}

vehicle_mesh_cache_store :: proc(mesh: ^vehicles.Libellula_Mesh, path: string) -> bool {
    if mesh == nil || path == "" do return false
    vertices, triangles := vehicle_mesh_cache_payload(mesh)
    if len(vertices) == 0 || len(triangles) == 0 do return false
    directory, directory_ok := vehicle_mesh_cache_directory(context.temp_allocator)
    if !directory_ok do return false
    directory_error := os.make_directory_all(directory)
    if directory_error != nil && directory_error != .Exist do return false
    header := Vehicle_Mesh_Cache_Header{
        magic           = VEHICLE_MESH_CACHE_MAGIC,
        version         = VEHICLE_MESH_CACHE_VERSION,
        vertex_stride   = u32(size_of(vehicles.Mesh_Vertex)),
        triangle_stride = u32(size_of(vehicles.Mesh_Triangle)),
        vertex_count    = u32(mesh.vertex_count),
        triangle_count  = u32(mesh.triangle_count),
        payload_size    = u64(len(vertices) + len(triangles)),
        checksum        = vehicle_mesh_cache_checksum(vertices, triangles),
    }
    temporary, temporary_error := strings.concatenate({path, ".tmp"}, context.temp_allocator)
    if temporary_error != nil do return false
    file, create_error := os.create(temporary)
    if create_error != nil do return false
    header_bytes := mem.slice_ptr(cast([^]u8)&header, size_of(header))
    header_written, header_error := os.write(file, header_bytes)
    vertices_written, vertices_error := os.write(file, vertices)
    triangles_written, triangles_error := os.write(file, triangles)
    close_error := os.close(file)
    if header_error != nil || vertices_error != nil || triangles_error != nil || close_error != nil ||
       header_written != len(header_bytes) || vertices_written != len(vertices) || triangles_written != len(triangles) {
        _ = os.remove(temporary)
        return false
    }
    if os.rename(temporary, path) == nil do return true
    _ = os.remove(path)
    return os.rename(temporary, path) == nil
}

aircraft_mesh_cache_load :: proc(mesh: ^vehicles.Aircraft_Mesh, path: string, version: u32) -> bool {
    if mesh == nil || path == "" do return false
    data, read_error := os.read_entire_file(path, context.temp_allocator)
    if read_error != nil || len(data) < size_of(Vehicle_Mesh_Cache_Header) do return false
    header := cast(^Vehicle_Mesh_Cache_Header)raw_data(data)
    if header.magic != VEHICLE_MESH_CACHE_MAGIC ||
       header.version != version ||
       header.vertex_stride != u32(size_of(vehicles.Mesh_Vertex)) ||
       header.triangle_stride != u32(size_of(vehicles.Mesh_Triangle)) ||
       header.vertex_count == 0 || int(header.vertex_count) > len(mesh.vertices) ||
       header.triangle_count == 0 || int(header.triangle_count) > len(mesh.triangles) {
        return false
    }
    vertex_size := int(header.vertex_count) * size_of(vehicles.Mesh_Vertex)
    triangle_size := int(header.triangle_count) * size_of(vehicles.Mesh_Triangle)
    if header.payload_size != u64(vertex_size + triangle_size) ||
       len(data) != size_of(Vehicle_Mesh_Cache_Header) + vertex_size + triangle_size {
        return false
    }
    payload := data[size_of(Vehicle_Mesh_Cache_Header):]
    if hash.fnv64a(payload) != header.checksum do return false
    cached_vertices := mem.slice_ptr(cast([^]vehicles.Mesh_Vertex)raw_data(payload[:vertex_size]), int(header.vertex_count))
    cached_triangles := mem.slice_ptr(
        cast([^]vehicles.Mesh_Triangle)raw_data(payload[vertex_size:]),
        int(header.triangle_count),
    )
    for vertex in cached_vertices {
        for component in vertex.position {
            if math.is_nan(component) || math.is_inf(component, 0) do return false
        }
        for component in vertex.normal {
            if math.is_nan(component) || math.is_inf(component, 0) do return false
        }
        for component in vertex.uv {
            if math.is_nan(component) || math.is_inf(component, 0) do return false
        }
        if int(vertex.part) > int(vehicles.Aircraft_Mesh_Part.Lift_Frame) ||
           int(vertex.animation_group) > int(vehicles.Mesh_Animation_Group.Libellula_Mk2_Rear_Rotor) {
            return false
        }
    }
    for triangle in cached_triangles {
        if u32(triangle.a) >= header.vertex_count ||
           u32(triangle.b) >= header.vertex_count ||
           u32(triangle.c) >= header.vertex_count {
            return false
        }
    }
    copy(mesh.vertices[:int(header.vertex_count)], cached_vertices)
    copy(mesh.triangles[:int(header.triangle_count)], cached_triangles)
    mesh.vertex_count = int(header.vertex_count)
    mesh.triangle_count = int(header.triangle_count)
    return true
}

aircraft_mesh_cache_store :: proc(mesh: ^vehicles.Aircraft_Mesh, path: string, version: u32) -> bool {
    if mesh == nil || path == "" || mesh.vertex_count <= 0 || mesh.triangle_count <= 0 do return false
    vertices := mem.slice_ptr(
        cast([^]u8)&mesh.vertices[0],
        mesh.vertex_count * size_of(vehicles.Mesh_Vertex),
    )
    triangles := mem.slice_ptr(
        cast([^]u8)&mesh.triangles[0],
        mesh.triangle_count * size_of(vehicles.Mesh_Triangle),
    )
    directory, directory_ok := vehicle_mesh_cache_directory(context.temp_allocator)
    if !directory_ok do return false
    directory_error := os.make_directory_all(directory)
    if directory_error != nil && directory_error != .Exist do return false
    header := Vehicle_Mesh_Cache_Header{
        magic           = VEHICLE_MESH_CACHE_MAGIC,
        version         = version,
        vertex_stride   = u32(size_of(vehicles.Mesh_Vertex)),
        triangle_stride = u32(size_of(vehicles.Mesh_Triangle)),
        vertex_count    = u32(mesh.vertex_count),
        triangle_count  = u32(mesh.triangle_count),
        payload_size    = u64(len(vertices) + len(triangles)),
        checksum        = vehicle_mesh_cache_checksum(vertices, triangles),
    }
    temporary, temporary_error := strings.concatenate({path, ".tmp"}, context.temp_allocator)
    if temporary_error != nil do return false
    file, create_error := os.create(temporary)
    if create_error != nil do return false
    header_bytes := mem.slice_ptr(cast([^]u8)&header, size_of(header))
    header_written, header_error := os.write(file, header_bytes)
    vertices_written, vertices_error := os.write(file, vertices)
    triangles_written, triangles_error := os.write(file, triangles)
    close_error := os.close(file)
    if header_error != nil || vertices_error != nil || triangles_error != nil || close_error != nil ||
       header_written != len(header_bytes) || vertices_written != len(vertices) || triangles_written != len(triangles) {
        _ = os.remove(temporary)
        return false
    }
    if os.rename(temporary, path) == nil do return true
    _ = os.remove(path)
    return os.rename(temporary, path) == nil
}
