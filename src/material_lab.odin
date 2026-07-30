package main

import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import "core:fmt"
import "core:image"
import _ "core:image/png"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import rl "zelda_engine:canvas2d"

MATERIAL_LAB_CAPACITY :: 32
MATERIAL_LAB_NAME_CAPACITY :: 48
MATERIAL_LAB_VERSION :: u32(2)
MATERIAL_LAB_MAGIC :: [8]u8{'A', 'D', 'R', 'M', 'A', 'T', 'L', 'B'}
MATERIAL_LAB_SLIDER_COUNT :: 5
MATERIAL_LAB_MAP_COUNT :: 4
MATERIAL_LAB_PATH_CAPACITY :: 256

Material_Lab_Map_Kind :: enum u8 {
    Albedo,
    Specular,
    Roughness,
    Normal,
}

MATERIAL_LAB_MAP_NAMES := [MATERIAL_LAB_MAP_COUNT]string{"albedo", "specular", "roughness", "normal"}

Material_Lab_Map_Path :: struct {
    bytes:  [MATERIAL_LAB_PATH_CAPACITY]u8,
    length: u16,
}

Material_Lab_Material :: struct {
    name:        [MATERIAL_LAB_NAME_CAPACITY]u8,
    name_length: u8,
    color:       [3]u8,
    metallic:    f32,
    roughness:   f32,
    maps:        [MATERIAL_LAB_MAP_COUNT]Material_Lab_Map_Path,
}

Material_Lab_Library :: struct {
    count:     u32,
    materials: [MATERIAL_LAB_CAPACITY]Material_Lab_Material,
}

Material_Lab_File :: struct {
    magic:    [8]u8,
    version:  u32,
    library:  Material_Lab_Library,
    checksum: u64,
}

Material_Lab_State :: struct {
    library:      Material_Lab_Library,
    selected:     int,
    dragging:     int,
    name_editing: bool,
    dirty:        bool,
    status:       cstring,
    status_until: f64,
    loaded_maps:  [MATERIAL_LAB_MAP_COUNT]^image.Image,
    loaded_index: int,
    map_revision: u64,
    orbit_yaw:     f32,
    orbit_pitch:   f32,
    orbit_distance: f32,
    lighting_minutes: f32,
}

material_lab: Material_Lab_State

material_lab_name :: proc(material: ^Material_Lab_Material) -> string {
    if material == nil do return ""
    return string(material.name[:min(int(material.name_length), len(material.name))])
}

material_lab_set_name :: proc(material: ^Material_Lab_Material, name: string) {
    if material == nil do return
    material.name = {}
    material.name_length = u8(min(len(name), len(material.name)))
    copy(material.name[:material.name_length], transmute([]u8)name[:material.name_length])
}

material_lab_map_path :: proc(material: ^Material_Lab_Material, kind: Material_Lab_Map_Kind) -> string {
    if material == nil do return ""
    path := &material.maps[int(kind)]
    return string(path.bytes[:min(int(path.length), len(path.bytes))])
}

material_lab_set_map_path :: proc(
    material: ^Material_Lab_Material,
    kind: Material_Lab_Map_Kind,
    value: string,
) -> bool {
    if material == nil || value == "" || len(value) >= MATERIAL_LAB_PATH_CAPACITY do return false
    path := &material.maps[int(kind)]
    path^ = {}
    path.length = u16(len(value))
    copy(path.bytes[:path.length], transmute([]u8)value)
    return true
}

material_lab_map_kind :: proc(name: string) -> (Material_Lab_Map_Kind, bool) {
    for candidate, index in MATERIAL_LAB_MAP_NAMES {
        if strings.equal_fold(name, candidate) do return Material_Lab_Map_Kind(index), true
    }
    return {}, false
}

material_lab_find :: proc(name: string) -> int {
    for index in 0 ..< int(material_lab.library.count) {
        if strings.equal_fold(material_lab_name(&material_lab.library.materials[index]), name) do return index
    }
    return -1
}

material_lab_attach_map :: proc(material_name, map_name, path: string) -> (int, bool) {
    index := material_lab_find(material_name)
    kind, kind_ok := material_lab_map_kind(map_name)
    if index < 0 || !kind_ok || !os.exists(path) do return -1, false
    if !material_lab_set_map_path(&material_lab.library.materials[index], kind, path) do return -1, false
    material_lab.selected = index
    material_lab.dirty = true
    material_lab_maps_load()
    return index, true
}

material_lab_maps_destroy :: proc() {
    for &loaded in material_lab.loaded_maps {
        if loaded != nil do image.destroy(loaded)
        loaded = nil
    }
    material_lab.loaded_index = -1
}

material_lab_maps_load :: proc() {
    material_lab_maps_destroy()
    material := material_lab_current()
    if material == nil do return
    for index in 0 ..< MATERIAL_LAB_MAP_COUNT {
        path := material_lab_map_path(material, Material_Lab_Map_Kind(index))
        if path == "" do continue
        decoded, err := image.load(path, {.alpha_add_if_missing})
        if err == nil do material_lab.loaded_maps[index] = decoded
    }
    material_lab.loaded_index = material_lab.selected
    material_lab.map_revision += 1
}

material_lab_map_sample :: proc(kind: Material_Lab_Map_Kind, u, v: f32) -> [4]f32 {
    loaded := material_lab.loaded_maps[int(kind)]
    if loaded == nil || loaded.width <= 0 || loaded.height <= 0 do return {}
    x := clamp(int(u * f32(loaded.width)), 0, loaded.width - 1)
    y := clamp(int(v * f32(loaded.height)), 0, loaded.height - 1)
    offset := (y * loaded.width + x) * 4
    pixels := loaded.pixels.buf[:]
    return {
        f32(pixels[offset]) / 255,
        f32(pixels[offset + 1]) / 255,
        f32(pixels[offset + 2]) / 255,
        f32(pixels[offset + 3]) / 255,
    }
}

material_lab_make :: proc(name: string, color: [3]u8, metallic, roughness: f32) -> Material_Lab_Material {
    result := Material_Lab_Material {
        color     = color,
        metallic  = clamp(metallic, 0, 1),
        roughness = clamp(roughness, .04, 1),
    }
    material_lab_set_name(&result, name)
    return result
}

material_lab_defaults :: proc() -> Material_Lab_Library {
    result: Material_Lab_Library
    defaults := [?]Material_Lab_Material {
        material_lab_make("Warm plaster", {214, 194, 157}, 0, .88),
        material_lab_make("Aged bronze", {125, 91, 51}, .82, .38),
        material_lab_make("Glazed ceramic", {52, 132, 145}, 0, .18),
        material_lab_make("Brushed aluminum", {174, 181, 180}, .92, .29),
        material_lab_make("Oxide red paint", {151, 53, 39}, .08, .57),
    }
    result.count = u32(len(defaults))
    for material, index in defaults do result.materials[index] = material
    return result
}

material_lab_checksum :: proc(library: ^Material_Lab_Library) -> u64 {
    bytes := mem.slice_ptr(cast([^]u8)library, size_of(library^))
    hash: u64 = 14695981039346656037
    for byte in bytes do hash = (hash ~ u64(byte)) * 1099511628211
    return hash
}

material_lab_save_directory :: proc(allocator := context.allocator) -> (string, bool) {
    base, err := os.user_data_dir(allocator)
    if err != nil || base == "" do return "", false
    path, concatenate_err := strings.concatenate({base, "/Adriatic"}, allocator)
    return path, concatenate_err == nil
}

material_lab_save_path :: proc(allocator := context.allocator) -> (string, bool) {
    directory, ok := material_lab_save_directory(allocator)
    if !ok do return "", false
    path, err := strings.concatenate({directory, "/brdf-materials.bin"}, allocator)
    return path, err == nil
}

material_lab_save_to_path :: proc(library: ^Material_Lab_Library, path: string) -> bool {
    if library == nil || path == "" do return false
    file_data := Material_Lab_File {
        magic   = MATERIAL_LAB_MAGIC,
        version = MATERIAL_LAB_VERSION,
        library = library^,
    }
    file_data.checksum = material_lab_checksum(&file_data.library)
    bytes := mem.slice_ptr(cast([^]u8)&file_data, size_of(file_data))
    temporary, temporary_err := strings.concatenate({path, ".tmp"}, context.temp_allocator)
    if temporary_err != nil do return false
    file, create_err := os.create(temporary)
    if create_err != nil do return false
    written, write_err := os.write(file, bytes)
    sync_err := os.sync(file)
    close_err := os.close(file)
    if write_err != nil || sync_err != nil || close_err != nil || written != len(bytes) {
        _ = os.remove(temporary)
        return false
    }
    if os.rename(temporary, path) == nil do return true
    _ = os.remove(path)
    return os.rename(temporary, path) == nil
}

material_lab_load_from_path :: proc(library: ^Material_Lab_Library, path: string) -> bool {
    if library == nil || path == "" do return false
    bytes, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil || len(bytes) != size_of(Material_Lab_File) do return false
    file_data := cast(^Material_Lab_File)raw_data(bytes)
    if file_data.magic != MATERIAL_LAB_MAGIC ||
       file_data.version != MATERIAL_LAB_VERSION ||
       file_data.library.count > MATERIAL_LAB_CAPACITY ||
       material_lab_checksum(&file_data.library) != file_data.checksum {
        return false
    }
    for index in 0 ..< int(file_data.library.count) {
        material := &file_data.library.materials[index]
        if int(material.name_length) > len(material.name) ||
           material.metallic < 0 ||
           material.metallic > 1 ||
           material.roughness < .04 ||
           material.roughness > 1 {
            return false
        }
    }
    library^ = file_data.library
    return true
}

material_lab_save :: proc() -> bool {
    directory, directory_ok := material_lab_save_directory(context.temp_allocator)
    if !directory_ok do return false
    directory_err := os.make_directory_all(directory)
    if directory_err != nil && directory_err != .Exist do return false
    path, path_ok := material_lab_save_path(context.temp_allocator)
    if !path_ok do return false
    return material_lab_save_to_path(&material_lab.library, path)
}

material_lab_load :: proc() -> bool {
    path, ok := material_lab_save_path(context.temp_allocator)
    return ok && material_lab_load_from_path(&material_lab.library, path)
}

material_lab_status :: proc(message: cstring) {
    material_lab.status = message
    material_lab.status_until = rl.GetTime() + 2.5
}

material_lab_current :: proc() -> ^Material_Lab_Material {
    if material_lab.selected < 0 || material_lab.selected >= int(material_lab.library.count) do return nil
    return &material_lab.library.materials[material_lab.selected]
}

material_lab_update_camera :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.camera_pose = third_person.camera_pose(
        third_person.Vec3{0, 1.25, 0},
        {
            yaw_radians   = material_lab.orbit_yaw,
            pitch_radians = material_lab.orbit_pitch,
            distance      = material_lab.orbit_distance,
        },
    )
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
}

material_lab_lighting_bounds :: proc(width: i32) -> rl.Rectangle {
    return {f32(width) - 300, 28, 270, 58}
}

material_lab_configure :: proc(editor: ^Editor, _: string) -> bool {
    if editor == nil do return false
    material_lab = {
        selected     = 0,
        dragging     = -1,
        loaded_index = -1,
        orbit_yaw = -.66,
        orbit_pitch = .24,
        orbit_distance = 9.2,
        lighting_minutes = 10 * 60 + 20,
    }
    if !material_lab_load() {
        material_lab.library = material_lab_defaults()
        material_lab.dirty = true
        material_lab_status("STARTER LIBRARY")
    } else {
        material_lab_status("LIBRARY LOADED")
    }
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    atmosphere.set_world_minutes(&editor.atmosphere, material_lab.lighting_minutes)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    material_lab_update_camera(editor)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    _ = rl.StartTextInput()
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
    material_lab_maps_load()
    return true
}

material_lab_exit :: proc(_: ^Editor) {
    material_lab.dragging = -1
    material_lab.name_editing = false
    material_lab_maps_destroy()
    _ = rl.StopTextInput()
    _ = sdl.ShowCursor()
}

material_lab_add :: proc(copy_selected: bool) {
    if material_lab.library.count >= MATERIAL_LAB_CAPACITY {
        material_lab_status("LIBRARY FULL")
        return
    }
    index := int(material_lab.library.count)
    if copy_selected && material_lab_current() != nil {
        material_lab.library.materials[index] = material_lab_current()^
        material_lab_set_name(&material_lab.library.materials[index], "Material copy")
    } else {
        material_lab.library.materials[index] = material_lab_make("Untitled material", {176, 164, 138}, 0, .62)
    }
    material_lab.library.count += 1
    material_lab.selected = index
    material_lab.dirty = true
    material_lab.name_editing = true
    material_lab_maps_load()
}

material_lab_create :: proc(name: string, color: [3]u8, metallic, roughness: f32) -> (int, bool) {
    if name == "" || material_lab_find(name) >= 0 || material_lab.library.count >= MATERIAL_LAB_CAPACITY {
        return -1, false
    }
    index := int(material_lab.library.count)
    material_lab.library.materials[index] = material_lab_make(name, color, metallic, roughness)
    material_lab.library.count += 1
    material_lab.selected = index
    material_lab.dirty = true
    material_lab.name_editing = false
    material_lab_maps_load()
    return index, true
}

material_lab_delete :: proc() {
    if material_lab.library.count <= 1 || material_lab_current() == nil {
        material_lab_status("KEEP AT LEAST ONE")
        return
    }
    for index in material_lab.selected ..< int(material_lab.library.count) - 1 {
        material_lab.library.materials[index] = material_lab.library.materials[index + 1]
    }
    material_lab.library.count -= 1
    material_lab.library.materials[material_lab.library.count] = {}
    material_lab.selected = min(material_lab.selected, int(material_lab.library.count) - 1)
    material_lab.dirty = true
    material_lab_maps_load()
}

material_lab_append_name :: proc(text: string) {
    material := material_lab_current()
    if material == nil || text == "" do return
    remaining := len(material.name) - int(material.name_length)
    count := min(remaining, len(text))
    if count <= 0 do return
    copy(material.name[material.name_length:], transmute([]u8)text[:count])
    material.name_length += u8(count)
    material_lab.dirty = true
}

material_lab_backspace_name :: proc() {
    material := material_lab_current()
    if material == nil || material.name_length == 0 do return
    material.name_length -= 1
    for material.name_length > 0 && (material.name[material.name_length] & 0xc0) == 0x80 {
        material.name_length -= 1
    }
    material.name[material.name_length] = 0
    material_lab.dirty = true
}

material_lab_layout :: proc(
    width, height: i32,
) -> (
    panel, list, name_box: rl.Rectangle,
    slider_x, slider_y, slider_w: f32,
) {
    panel = {22, 22, min(f32(width) - 44, f32(560)), min(f32(height) - 44, f32(610))}
    list = {panel.x + 20, panel.y + 84, 190, panel.height - 164}
    name_box = {panel.x + 230, panel.y + 84, panel.width - 250, 38}
    slider_x = panel.x + 310
    slider_y = panel.y + 166
    slider_w = panel.width - 340
    return
}

material_lab_slider_value :: proc(index: int) -> f32 {
    material := material_lab_current()
    if material == nil do return 0
    switch index {
    case 0:
        return f32(material.color[0]) / 255
    case 1:
        return f32(material.color[1]) / 255
    case 2:
        return f32(material.color[2]) / 255
    case 3:
        return material.metallic
    case 4:
        return material.roughness
    }
    return 0
}

material_lab_set_slider :: proc(index: int, normalized: f32) {
    material := material_lab_current()
    if material == nil do return
    value := clamp(normalized, 0, 1)
    switch index {
    case 0:
        material.color[0] = u8(value * 255 + .5)
    case 1:
        material.color[1] = u8(value * 255 + .5)
    case 2:
        material.color[2] = u8(value * 255 + .5)
    case 3:
        material.metallic = value
    case 4:
        material.roughness = max(value, f32(.04))
    }
    material_lab.dirty = true
}

material_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    width, height := rl.GetScreenWidth(), rl.GetScreenHeight()
    panel, list, name_box, slider_x, slider_y, slider_w := material_lab_layout(width, height)
    _ = panel
    mouse := rl.GetMousePosition()
    pressed := rl.IsMouseButtonPressed(.LEFT)
    lighting_bounds := material_lab_lighting_bounds(width)
    viewport_input := !rl.CheckCollisionPointRec(mouse, panel) &&
                      !rl.CheckCollisionPointRec(mouse, lighting_bounds)

    if viewport_input && rl.IsMouseButtonDown(.RIGHT) {
        mouse_delta := rl.GetMouseDelta()
        material_lab.orbit_yaw -= mouse_delta.x * .008
        material_lab.orbit_pitch = clamp(material_lab.orbit_pitch - mouse_delta.y * .006, -.55, 1.15)
        material_lab_update_camera(editor)
    }
    wheel := rl.GetMouseWheelMove()
    if viewport_input && math.abs(wheel) > .01 {
        if shift_key_down() {
            material_lab.lighting_minutes += wheel * 30
            atmosphere.set_world_minutes(&editor.atmosphere, material_lab.lighting_minutes)
        } else {
            material_lab.orbit_distance = clamp(
                material_lab.orbit_distance * f32(math.pow(.86, f64(wheel))),
                3.4,
                18,
            )
            material_lab_update_camera(editor)
        }
    }

    lighting_track := rl.Rectangle {
        lighting_bounds.x + 14,
        lighting_bounds.y + 35,
        lighting_bounds.width - 28,
        12,
    }
    if rl.IsMouseButtonDown(.LEFT) && rl.CheckCollisionPointRec(mouse, lighting_bounds) {
        normalized := clamp((mouse.x - lighting_track.x) / lighting_track.width, 0, 1)
        // Keep the useful daylight arc on one slider, from sunrise through sunset.
        material_lab.lighting_minutes = 6 * 60 + normalized * 12 * 60
        atmosphere.set_world_minutes(&editor.atmosphere, material_lab.lighting_minutes)
    }

    if material_lab.name_editing {
        _ = rl.SetTextInputArea(name_box, int(material_lab_current().name_length))
        material_lab_append_name(rl.GetTextInput())
        if rl.IsKeyPressed(.BACKSPACE) do material_lab_backspace_name()
        if rl.IsKeyPressed(.ENTER) do material_lab.name_editing = false
    }

    row_height := f32(34)
    if pressed && rl.CheckCollisionPointRec(mouse, list) {
        index := int((mouse.y - list.y) / row_height)
        if index >= 0 && index < int(material_lab.library.count) {
            material_lab.selected = index
            material_lab.name_editing = false
            material_lab_maps_load()
        }
    }
    if pressed && rl.CheckCollisionPointRec(mouse, name_box) do material_lab.name_editing = true

    buttons_y := panel.y + panel.height - 58
    new_button := rl.Rectangle{panel.x + 20, buttons_y, 82, 34}
    duplicate_button := rl.Rectangle{panel.x + 110, buttons_y, 100, 34}
    delete_button := rl.Rectangle{panel.x + 230, buttons_y, 82, 34}
    revert_button := rl.Rectangle{panel.x + 320, buttons_y, 82, 34}
    save_button := rl.Rectangle{panel.x + panel.width - 110, buttons_y, 90, 34}
    if pressed && rl.CheckCollisionPointRec(mouse, new_button) do material_lab_add(false)
    if pressed && rl.CheckCollisionPointRec(mouse, duplicate_button) do material_lab_add(true)
    if pressed && rl.CheckCollisionPointRec(mouse, delete_button) do material_lab_delete()
    if pressed && rl.CheckCollisionPointRec(mouse, revert_button) {
        if material_lab_load() {
            material_lab.selected = min(material_lab.selected, int(material_lab.library.count) - 1)
            material_lab.dirty = false
            material_lab_maps_load()
            material_lab_status("CHANGES REVERTED")
        } else {
            material_lab_status("NO SAVED LIBRARY")
        }
    }
    if pressed && rl.CheckCollisionPointRec(mouse, save_button) {
        if material_lab_save() {
            material_lab.dirty = false
            material_lab_status("LIBRARY SAVED")
        } else {
            material_lab_status("SAVE FAILED")
        }
    }

    if pressed {
        for index in 0 ..< MATERIAL_LAB_SLIDER_COUNT {
            bounds := rl.Rectangle{slider_x, slider_y + f32(index) * 54 - 12, slider_w, 36}
            if rl.CheckCollisionPointRec(mouse, bounds) {
                material_lab.dragging = index
                material_lab_set_slider(index, (mouse.x - slider_x) / slider_w)
                break
            }
        }
    }
    if rl.IsMouseButtonDown(.LEFT) && material_lab.dragging >= 0 {
        material_lab_set_slider(material_lab.dragging, (mouse.x - slider_x) / slider_w)
    }
    if rl.IsMouseButtonReleased(.LEFT) do material_lab.dragging = -1
    if rl.IsKeyPressed(.ESCAPE) {
        if material_lab.name_editing {
            material_lab.name_editing = false
        } else {
            lab_scene_exit_to_main_menu(editor)
        }
    }
}

material_lab_sphere_vertex :: proc(
    point, normal: third_person.Vec3,
    tangent, bitangent: third_person.Vec3,
    u, v: f32,
    material: ^Material_Lab_Material,
) -> World_Vertex {
    color := [4]f32{f32(material.color[0]) / 255, f32(material.color[1]) / 255, f32(material.color[2]) / 255, 1}
    vertex := world_greek_asset_vertex(point, color, normal, material.metallic, material.roughness)
    vertex.kind = .Material_Lab
    vertex.uv = {u, v}
    return vertex
}

material_lab_sphere :: proc(center: third_person.Vec3, radius: f32, material: ^Material_Lab_Material) {
    if material == nil do return
    LATITUDES :: 18
    LONGITUDES :: 28
    for latitude in 0 ..< LATITUDES {
        v0, v1 := f32(latitude) / LATITUDES, f32(latitude + 1) / LATITUDES
        phi0, phi1 := -math.PI * .5 + v0 * math.PI, -math.PI * .5 + v1 * math.PI
        for longitude in 0 ..< LONGITUDES {
            u0, u1 := f32(longitude) / LONGITUDES, f32(longitude + 1) / LONGITUDES
            theta0, theta1 := u0 * math.PI * 2, u1 * math.PI * 2
            n00 := third_person.Vec3 {
                math.cos(phi0) * math.cos(theta0),
                math.sin(phi0),
                math.cos(phi0) * math.sin(theta0),
            }
            n01 := third_person.Vec3 {
                math.cos(phi0) * math.cos(theta1),
                math.sin(phi0),
                math.cos(phi0) * math.sin(theta1),
            }
            n10 := third_person.Vec3 {
                math.cos(phi1) * math.cos(theta0),
                math.sin(phi1),
                math.cos(phi1) * math.sin(theta0),
            }
            n11 := third_person.Vec3 {
                math.cos(phi1) * math.cos(theta1),
                math.sin(phi1),
                math.cos(phi1) * math.sin(theta1),
            }
            t0 := third_person.Vec3{-math.sin(theta0), 0, math.cos(theta0)}
            t1 := third_person.Vec3{-math.sin(theta1), 0, math.cos(theta1)}
            b00 := third_person.Vec3 {
                -math.sin(phi0) * math.cos(theta0),
                math.cos(phi0),
                -math.sin(phi0) * math.sin(theta0),
            }
            b01 := third_person.Vec3 {
                -math.sin(phi0) * math.cos(theta1),
                math.cos(phi0),
                -math.sin(phi0) * math.sin(theta1),
            }
            b10 := third_person.Vec3 {
                -math.sin(phi1) * math.cos(theta0),
                math.cos(phi1),
                -math.sin(phi1) * math.sin(theta0),
            }
            b11 := third_person.Vec3 {
                -math.sin(phi1) * math.cos(theta1),
                math.cos(phi1),
                -math.sin(phi1) * math.sin(theta1),
            }
            append(
                &world_renderer.vertices,
                material_lab_sphere_vertex(center + n00 * radius, n00, t0, b00, u0, v0, material),
                material_lab_sphere_vertex(center + n10 * radius, n10, t0, b10, u0, v1, material),
                material_lab_sphere_vertex(center + n11 * radius, n11, t1, b11, u1, v1, material),
                material_lab_sphere_vertex(center + n00 * radius, n00, t0, b00, u0, v0, material),
                material_lab_sphere_vertex(center + n11 * radius, n11, t1, b11, u1, v1, material),
                material_lab_sphere_vertex(center + n01 * radius, n01, t1, b01, u1, v0, material),
            )
        }
    }
}

world_material_lab :: proc(_: ^Editor) {
    world_box({0, -.24, 0}, {11, .40, 9}, {105, 109, 105, 255})
    world_box({0, .01, 0}, {4.5, .08, 4.5}, {175, 170, 151, 255})
    material_lab_sphere({0, 1.55, 0}, 1.5, material_lab_current())
    // Neutral cards make highlights and reflected contrast readable.
    world_box({-3.25, 1.35, -.75}, {.12, 2.7, 3.8}, {224, 221, 205, 255})
    world_box({3.25, 1.35, -.75}, {.12, 2.7, 3.8}, {43, 48, 49, 255})
}

material_lab_button :: proc(bounds: rl.Rectangle, label: cstring, accent: bool = false) {
    hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill := accent ? rl.Color{133, 91, 42, 255} : rl.Color{34, 43, 43, 255}
    if hovered do fill = accent ? rl.Color{161, 111, 51, 255} : rl.Color{48, 59, 58, 255}
    rl.DrawRectangleRounded(bounds, .20, 6, fill)
    rl.DrawRectangleRoundedLinesEx(
        bounds,
        .20,
        6,
        1,
        accent ? rl.Color{240, 194, 111, 255} : rl.Color{102, 125, 121, 255},
    )
    size := ui_measure_text(.Label, label, .27)
    ui_draw_text(.Label, label, {bounds.x + (bounds.width - size.x) * .5, bounds.y + 10}, .27, {234, 231, 213, 255})
}

material_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel, list, name_box, slider_x, slider_y, slider_w := material_lab_layout(width, height)
    rl.DrawRectangleRounded(panel, .045, 10, {15, 23, 24, 242})
    rl.DrawRectangleRoundedLinesEx(panel, .045, 10, 1, {143, 119, 75, 255})
    lighting_bounds := material_lab_lighting_bounds(width)
    rl.DrawRectangleRounded(lighting_bounds, .12, 8, {15, 23, 24, 230})
    ui_draw_text(.Label, "LIGHTING", {lighting_bounds.x + 14, lighting_bounds.y + 10}, .25, {240, 194, 111, 255})
    hour := material_lab.lighting_minutes / 60
    ui_draw_text(
        .Data,
        fmt.ctprintf("%02d:%02d", int(hour), int((hour - f32(int(hour))) * 60)),
        {lighting_bounds.x + lighting_bounds.width - 56, lighting_bounds.y + 10},
        .19,
        {190, 198, 190, 255},
    )
    light_normalized := clamp((material_lab.lighting_minutes - 6 * 60) / (12 * 60), 0, 1)
    light_track := rl.Rectangle{lighting_bounds.x + 14, lighting_bounds.y + 39, lighting_bounds.width - 28, 7}
    rl.DrawRectangleRounded(light_track, 1, 4, {48, 57, 57, 255})
    rl.DrawRectangleRounded(
        {light_track.x, light_track.y, light_track.width * light_normalized, light_track.height},
        1,
        4,
        {240, 194, 111, 255},
    )
    rl.DrawCircleV(
        {light_track.x + light_track.width * light_normalized, light_track.y + light_track.height * .5},
        7,
        {239, 232, 210, 255},
    )
    ui_draw_text(.Label, "BRDF MATERIAL LAB", {panel.x + 20, panel.y + 20}, .58, {240, 194, 111, 255})
    ui_draw_text(
        .Data,
        "BUILD • COMPARE • SAVE TO YOUR LIBRARY",
        {panel.x + 20, panel.y + 50},
        .22,
        {150, 169, 164, 255},
    )

    rl.DrawRectangleRounded(list, .035, 6, {9, 15, 16, 255})
    row_height := f32(34)
    for index in 0 ..< int(material_lab.library.count) {
        bounds := rl.Rectangle{list.x + 4, list.y + f32(index) * row_height + 3, list.width - 8, row_height - 5}
        selected := material_lab.selected == index
        if selected || rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {
            rl.DrawRectangleRounded(bounds, .16, 5, selected ? rl.Color{87, 66, 36, 255} : rl.Color{28, 38, 38, 255})
        }
        swatch := material_lab.library.materials[index].color
        rl.DrawCircleV({bounds.x + 14, bounds.y + bounds.height * .5}, 6, {swatch[0], swatch[1], swatch[2], 255})
        ui_draw_text(
            .Label,
            fmt.ctprintf("%02d  %s", index + 1, material_lab_name(&material_lab.library.materials[index])),
            {bounds.x + 26, bounds.y + 9},
            .25,
            selected ? rl.Color{247, 218, 157, 255} : rl.Color{198, 207, 200, 255},
        )
    }

    rl.DrawRectangleRounded(name_box, .14, 6, {8, 15, 16, 255})
    rl.DrawRectangleRoundedLinesEx(
        name_box,
        .14,
        6,
        1,
        material_lab.name_editing ? rl.Color{240, 194, 111, 255} : rl.Color{74, 93, 91, 255},
    )
    name := material_lab_current() == nil ? "" : material_lab_name(material_lab_current())
    ui_draw_text(
        .Label,
        fmt.ctprintf("%s%s", name, material_lab.name_editing && int(rl.GetTime() * 2) % 2 == 0 ? "_" : ""),
        {name_box.x + 12, name_box.y + 12},
        .31,
        {232, 229, 211, 255},
    )

    labels := [?]cstring{"RED", "GREEN", "BLUE", "METALLIC", "ROUGHNESS"}
    colors := [?]rl.Color {
        {198, 69, 55, 255},
        {70, 164, 102, 255},
        {65, 126, 190, 255},
        {210, 181, 119, 255},
        {164, 179, 174, 255},
    }
    for label, index in labels {
        y := slider_y + f32(index) * 54
        value := material_lab_slider_value(index)
        ui_draw_text(.Label, label, {panel.x + 230, y - 7}, .28, {179, 190, 185, 255})
        rl.DrawRectangleRounded({slider_x, y, slider_w, 9}, 1, 4, {48, 57, 57, 255})
        rl.DrawRectangleRounded({slider_x, y, slider_w * value, 9}, 1, 4, colors[index])
        rl.DrawCircleV({slider_x + slider_w * value, y + 4.5}, 8, {239, 232, 210, 255})
        value_text := index < 3 ? fmt.ctprintf("%d", int(value * 255 + .5)) : fmt.ctprintf("%.2f", value)
        ui_draw_text(.Data, value_text, {slider_x + slider_w - 36, y - 20}, .21, {151, 168, 163, 255})
    }

    material := material_lab_current()
    if material != nil {
        swatch_bounds := rl.Rectangle{panel.x + 230, panel.y + 437, panel.width - 250, 38}
        rl.DrawRectangleRounded(swatch_bounds, .16, 6, {material.color[0], material.color[1], material.color[2], 255})
        contrast :=
            (int(material.color[0]) + int(material.color[1]) + int(material.color[2])) > 390 ? rl.Color{18, 25, 25, 255} : rl.Color{242, 239, 221, 255}
        ui_draw_text(
            .Data,
            fmt.ctprintf(
                "#%02X%02X%02X  M %.2f  R %.2f",
                material.color[0],
                material.color[1],
                material.color[2],
                material.metallic,
                material.roughness,
            ),
            {swatch_bounds.x + 12, swatch_bounds.y + 13},
            .22,
            contrast,
        )
        for map_name, index in MATERIAL_LAB_MAP_NAMES {
            attached := material_lab_map_path(material, Material_Lab_Map_Kind(index)) != ""
            ui_draw_text(
                .Data,
                fmt.ctprintf("%s %s", attached ? "●" : "○", map_name),
                {panel.x + 230 + f32(index) * 76, panel.y + 488},
                .17,
                attached ? rl.Color{240, 194, 111, 255} : rl.Color{116, 133, 130, 255},
            )
        }
    }

    buttons_y := panel.y + panel.height - 58
    material_lab_button({panel.x + 20, buttons_y, 82, 34}, "NEW")
    material_lab_button({panel.x + 110, buttons_y, 100, 34}, "DUPLICATE")
    material_lab_button({panel.x + 230, buttons_y, 82, 34}, "DELETE")
    material_lab_button({panel.x + 320, buttons_y, 82, 34}, "REVERT")
    material_lab_button(
        {panel.x + panel.width - 110, buttons_y, 90, 34},
        material_lab.dirty ? "SAVE *" : "SAVED",
        true,
    )
    if material_lab.status != nil && rl.GetTime() < material_lab.status_until {
        ui_draw_text(
            .Data,
            material_lab.status,
            {panel.x + panel.width - 152, panel.y + 54},
            .22,
            {240, 194, 111, 255},
        )
    }
    ui_draw_text(
        .Data,
        "RIGHT-DRAG  ORBIT   WHEEL  ZOOM   SHIFT+WHEEL  LIGHT   ESC  EXIT",
        {f32(width) - 520, f32(height) - 27},
        .20,
        {190, 198, 190, 255},
    )
}
