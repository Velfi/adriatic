package main

import atmosphere "../packages/atmosphere"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:image"
import _ "core:image/png"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"

MATERIAL_LAB_CAPACITY :: 4096
MATERIAL_LAB_LEGACY_CAPACITY :: 32
MATERIAL_LAB_NAME_CAPACITY :: 48
MATERIAL_LAB_TAGS_CAPACITY :: 96
MATERIAL_LAB_VERSION :: u32(4)
MATERIAL_LAB_PREVIOUS_VERSION :: u32(3)
MATERIAL_LAB_LEGACY_VERSION :: u32(2)
MATERIAL_LAB_MAGIC :: [8]u8{'A', 'D', 'R', 'M', 'A', 'T', 'L', 'B'}
MATERIAL_LAB_SLIDER_COUNT :: 5
MATERIAL_LAB_MAP_COUNT :: 4
MATERIAL_LAB_PATH_CAPACITY :: 256
MATERIAL_LAB_SEARCH_CAPACITY :: 48

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
    tags:        [MATERIAL_LAB_TAGS_CAPACITY]u8,
    tags_length: u8,
    color:       [3]u8,
    metallic:    f32,
    roughness:   f32,
    maps:        [MATERIAL_LAB_MAP_COUNT]Material_Lab_Map_Path,
}

Material_Lab_Previous_Material :: struct {
    name:        [MATERIAL_LAB_NAME_CAPACITY]u8,
    name_length: u8,
    color:       [3]u8,
    metallic:    f32,
    roughness:   f32,
    maps:        [MATERIAL_LAB_MAP_COUNT]Material_Lab_Map_Path,
}

Material_Lab_Library :: struct {
    count:     u32,
    materials: []Material_Lab_Material,
}

Material_Lab_File_Header :: struct {
    magic:    [8]u8,
    version:  u32,
    count:    u32,
    checksum: u64,
}

Material_Lab_Legacy_Library :: struct {
    count:     u32,
    materials: [MATERIAL_LAB_LEGACY_CAPACITY]Material_Lab_Previous_Material,
}

Material_Lab_Legacy_File :: struct {
    magic:    [8]u8,
    version:  u32,
    library:  Material_Lab_Legacy_Library,
    checksum: u64,
}

Material_Lab_State :: struct {
    library:                 Material_Lab_Library,
    selected:                int,
    dragging:                int,
    name_editing:            bool,
    tags_editing:            bool,
    dirty:                   bool,
    status:                  cstring,
    status_until:            f64,
    loaded_maps:             [MATERIAL_LAB_MAP_COUNT]^image.Image,
    loaded_index:            int,
    map_revision:            u64,
    orbit_yaw:               f32,
    orbit_pitch:             f32,
    orbit_distance:          f32,
    lighting_minutes:        f32,
    list_scroll_y:           f32,
    list_scroll_dragging:    bool,
    list_scroll_drag_offset: f32,
    search:                  [MATERIAL_LAB_SEARCH_CAPACITY]u8,
    search_length:           u8,
    search_editing:          bool,
}

material_lab: Material_Lab_State

material_lab_ensure_library :: proc() -> bool {
    if len(material_lab.library.materials) >= MATERIAL_LAB_CAPACITY do return true
    material_lab.library.materials = make([]Material_Lab_Material, MATERIAL_LAB_CAPACITY, context.allocator)
    if material_lab_load() do return true
    material_lab_defaults(&material_lab.library)
    material_lab.dirty = true
    return true
}

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

material_lab_tags :: proc(material: ^Material_Lab_Material) -> string {
    if material == nil do return ""
    return string(material.tags[:min(int(material.tags_length), len(material.tags))])
}

material_lab_set_tags :: proc(material: ^Material_Lab_Material, tags: string) {
    if material == nil do return
    material.tags = {}
    material.tags_length = u8(min(len(tags), len(material.tags)))
    copy(material.tags[:material.tags_length], transmute([]u8)tags[:material.tags_length])
}

material_lab_suggested_tags :: proc(material: ^Material_Lab_Material) -> string {
    name := material_lab_name(material)
    switch name {
    case "Warm plaster":
        return "plaster, wall, warm, matte, architectural"
    case "Aged bronze":
        return "metal, bronze, aged, patina"
    case "Glazed ceramic":
        return "ceramic, glazed, tile, glossy"
    case "Brushed aluminum":
        return "metal, aluminum, brushed, silver"
    case "Oxide red paint":
        return "paint, red, oxide, coated"
    case "Grass":
        return "grass, vegetation, ground, organic, green"
    case "Pale Adriatic Limestone":
        return "stone, limestone, pale, adriatic, masonry"
    case "Sun-Washed Stucco":
        return "stucco, plaster, sun-washed, wall, exterior"
    case "Arcade Terrazzo":
        return "terrazzo, stone, arcade, floor, aggregate"
    case "Exterior Forecourt Paving":
        return "paving, exterior, stone, forecourt, ground"
    case "Standing-Seam Roof":
        return "roof, metal, standing-seam, exterior"
    case "Monitor Tinted Glass":
        return "glass, tinted, window, transparent"
    case "Anodized Glazing Frame":
        return "metal, aluminum, anodized, frame, window"
    case "Teal Counter Tile":
        return "tile, ceramic, teal, counter, glossy"
    case "Counter Grout":
        return "grout, mortar, counter, matte"
    case "Counter Worktop Laminate":
        return "laminate, worktop, counter, wood"
    case "Postal Enamel Red":
        return "postal, enamel, red, painted, steel, mailbox"
    case "Postal Sorting Wood":
        return "postal, sorting, wood, beech, cubby, furniture, interior"
    case "Counter Toe-Kick":
        return "metal, counter, toe-kick, dark"
    case "Painted Steel":
        return "metal, steel, painted, coated"
    case "Dark Hardware":
        return "metal, hardware, dark, fixture"
    case "Bench Slatted Hardwood":
        return "wood, hardwood, bench, slatted, furniture"
    case "Fired Terracotta":
        return "terracotta, ceramic, fired, red, masonry"
    case "Moist Planter Soil":
        return "soil, earth, moist, planter, organic"
    case "Airport Asphalt":
        return "asphalt, airport, runway, road, ground"
    case "Pale Concrete Curb":
        return "concrete, curb, pale, road, masonry"
    case "Drainage Grate":
        return "metal, grate, drainage, road, hardware"
    case "Road Marking White":
        return "paint, road, marking, white, traffic"
    case "Road Marking Ochre":
        return "paint, road, marking, ochre, traffic"
    case "Aged Brass Details":
        return "metal, brass, aged, detail, patina"
    case "Aerodromo Enamel Face":
        return "enamel, sign, aerodromo, white, glossy"
    case "Aerodromo Enamel Rim":
        return "enamel, sign, aerodromo, red, metal"
    case "Exposed Salted Limestone":
        return "stone, limestone, salted, exposed, masonry"
    case "Foot-Polished Terrazzo":
        return "terrazzo, stone, polished, floor, aggregate"
    }
    if material != nil && material.metallic > .5 do return "metal, material"
    return "surface, material"
}

material_lab_tag_untagged_materials :: proc() -> int {
    tagged := 0
    for index in 0 ..< int(material_lab.library.count) {
        material := &material_lab.library.materials[index]
        suggested := material_lab_suggested_tags(material)
        existing := material_lab_tags(material)
        if existing != "" && existing != "surface, material" && existing != "metal, material" do continue
        if existing == suggested do continue
        material_lab_set_tags(material, suggested)
        tagged += 1
    }
    return tagged
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

material_lab_defaults :: proc(result: ^Material_Lab_Library) {
    defaults := [?]Material_Lab_Material {
        material_lab_make("Warm plaster", {214, 194, 157}, 0, .88),
        material_lab_make("Aged bronze", {125, 91, 51}, .82, .38),
        material_lab_make("Glazed ceramic", {52, 132, 145}, 0, .18),
        material_lab_make("Brushed aluminum", {174, 181, 180}, .92, .29),
        material_lab_make("Oxide red paint", {151, 53, 39}, .08, .57),
    }
    if result == nil || len(result.materials) < len(defaults) do return
    result.count = 0
    mem.zero_slice(result.materials)
    result.count = u32(len(defaults))
    for material, index in defaults do result.materials[index] = material
}

material_lab_checksum_bytes :: proc(bytes: []u8) -> u64 {
    hash: u64 = 14695981039346656037
    for byte in bytes do hash = (hash ~ u64(byte)) * 1099511628211
    return hash
}

material_lab_material_bytes :: proc(materials: []Material_Lab_Material) -> []u8 {
    if len(materials) == 0 do return nil
    return mem.slice_ptr(cast([^]u8)raw_data(materials), len(materials) * size_of(Material_Lab_Material))
}

material_lab_legacy_checksum :: proc(library: ^Material_Lab_Legacy_Library) -> u64 {
    return material_lab_checksum_bytes(mem.slice_ptr(cast([^]u8)library, size_of(library^)))
}

material_lab_material_valid :: proc(material: ^Material_Lab_Material) -> bool {
    return(
        material != nil &&
        int(material.name_length) <= len(material.name) &&
        int(material.tags_length) <= len(material.tags) &&
        material.metallic >= 0 &&
        material.metallic <= 1 &&
        material.roughness >= .04 &&
        material.roughness <= 1 \
    )
}

material_lab_previous_material_valid :: proc(material: ^Material_Lab_Previous_Material) -> bool {
    return(
        material != nil &&
        int(material.name_length) <= len(material.name) &&
        material.metallic >= 0 &&
        material.metallic <= 1 &&
        material.roughness >= .04 &&
        material.roughness <= 1 \
    )
}

material_lab_upgrade_previous_material :: proc(material: ^Material_Lab_Previous_Material) -> Material_Lab_Material {
    result: Material_Lab_Material
    if material == nil do return result
    result.name = material.name
    result.name_length = material.name_length
    result.color = material.color
    result.metallic = material.metallic
    result.roughness = material.roughness
    result.maps = material.maps
    return result
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
    if library == nil ||
       path == "" ||
       library.count > u32(len(library.materials)) ||
       library.count > MATERIAL_LAB_CAPACITY {
        return false
    }
    materials := library.materials[:int(library.count)]
    material_bytes := material_lab_material_bytes(materials)
    header := Material_Lab_File_Header {
        magic    = MATERIAL_LAB_MAGIC,
        version  = MATERIAL_LAB_VERSION,
        count    = library.count,
        checksum = material_lab_checksum_bytes(material_bytes),
    }
    header_size := size_of(Material_Lab_File_Header)
    bytes := make([]u8, header_size + len(material_bytes), context.temp_allocator)
    copy(bytes[:header_size], mem.slice_ptr(cast([^]u8)&header, header_size))
    copy(bytes[header_size:], material_bytes)
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
    if library == nil || len(library.materials) < MATERIAL_LAB_CAPACITY || path == "" do return false
    bytes, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil do return false
    if len(bytes) >= size_of(Material_Lab_File_Header) {
        header := cast(^Material_Lab_File_Header)raw_data(bytes)
        payload := bytes[size_of(Material_Lab_File_Header):]
        if header.magic == MATERIAL_LAB_MAGIC && header.version == MATERIAL_LAB_VERSION {
            if header.count > MATERIAL_LAB_CAPACITY ||
               len(payload) != int(header.count) * size_of(Material_Lab_Material) ||
               material_lab_checksum_bytes(payload) != header.checksum {
                return false
            }
            materials := mem.slice_ptr(cast([^]Material_Lab_Material)raw_data(payload), int(header.count))
            for index in 0 ..< len(materials) {
                if !material_lab_material_valid(&materials[index]) do return false
            }
            mem.zero_slice(library.materials)
            copy(library.materials[:int(header.count)], materials)
            library.count = header.count
            return true
        }
        if header.magic == MATERIAL_LAB_MAGIC && header.version == MATERIAL_LAB_PREVIOUS_VERSION {
            if header.count > MATERIAL_LAB_CAPACITY ||
               len(payload) != int(header.count) * size_of(Material_Lab_Previous_Material) ||
               material_lab_checksum_bytes(payload) != header.checksum {
                return false
            }
            materials := mem.slice_ptr(cast([^]Material_Lab_Previous_Material)raw_data(payload), int(header.count))
            mem.zero_slice(library.materials)
            for index in 0 ..< len(materials) {
                if !material_lab_previous_material_valid(&materials[index]) do return false
                library.materials[index] = material_lab_upgrade_previous_material(&materials[index])
            }
            library.count = header.count
            return true
        }
    }
    if len(bytes) != size_of(Material_Lab_Legacy_File) do return false
    legacy := cast(^Material_Lab_Legacy_File)raw_data(bytes)
    if legacy.magic != MATERIAL_LAB_MAGIC ||
       legacy.version != MATERIAL_LAB_LEGACY_VERSION ||
       legacy.library.count > MATERIAL_LAB_LEGACY_CAPACITY ||
       material_lab_legacy_checksum(&legacy.library) != legacy.checksum {
        return false
    }
    mem.zero_slice(library.materials)
    library.count = legacy.library.count
    for index in 0 ..< int(legacy.library.count) {
        if !material_lab_previous_material_valid(&legacy.library.materials[index]) {
            return false
        }
        library.materials[index] = material_lab_upgrade_previous_material(&legacy.library.materials[index])
    }
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
    material_lab.status_until = canvas2d.GetTime() + 2.5
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
            yaw_radians = material_lab.orbit_yaw,
            pitch_radians = material_lab.orbit_pitch,
            distance = material_lab.orbit_distance,
        },
    )
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
}

material_lab_lighting_bounds :: proc(width: i32) -> canvas2d.Rectangle {
    inspector_width := min(f32(350), max(f32(300), f32(width) * .25))
    inspector_x := f32(width) - inspector_width - 18
    return {inspector_x - 288, 28, 270, 58}
}

material_lab_configure :: proc(editor: ^Editor, _: string) -> bool {
    if editor == nil do return false
    materials := material_lab.library.materials
    material_lab = {
        selected         = 0,
        dragging         = -1,
        loaded_index     = -1,
        orbit_yaw        = -.66,
        orbit_pitch      = .24,
        orbit_distance   = 9.2,
        lighting_minutes = 10 * 60 + 20,
    }
    if len(materials) >= MATERIAL_LAB_CAPACITY {
        material_lab.library.materials = materials
    }
    _ = material_lab_ensure_library()
    if !material_lab_load() {
        material_lab_defaults(&material_lab.library)
        material_lab.dirty = true
        material_lab_status("STARTER LIBRARY")
    } else {
        tagged := material_lab_tag_untagged_materials()
        if tagged > 0 {
            if material_lab_save() {
                material_lab.dirty = false
                material_lab_status("MATERIALS TAGGED")
            } else {
                material_lab.dirty = true
                material_lab_status("TAGS NEED SAVE")
            }
        } else {
            material_lab_status("LIBRARY LOADED")
        }
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
    _ = canvas2d.StartTextInput()
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
    material_lab_maps_load()
    return true
}

material_lab_exit :: proc(_: ^Editor) {
    material_lab.dragging = -1
    material_lab.name_editing = false
    material_lab_maps_destroy()
    _ = canvas2d.StopTextInput()
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

material_lab_append_tags :: proc(text: string) {
    material := material_lab_current()
    if material == nil || text == "" do return
    remaining := len(material.tags) - int(material.tags_length)
    count := min(remaining, len(text))
    if count <= 0 do return
    copy(material.tags[material.tags_length:], transmute([]u8)text[:count])
    material.tags_length += u8(count)
    material_lab.dirty = true
}

material_lab_backspace_tags :: proc() {
    material := material_lab_current()
    if material == nil || material.tags_length == 0 do return
    material.tags_length -= 1
    for material.tags_length > 0 && (material.tags[material.tags_length] & 0xc0) == 0x80 {
        material.tags_length -= 1
    }
    material.tags[material.tags_length] = 0
    material_lab.dirty = true
}

material_lab_layout :: proc(
    width, height: i32,
) -> (
    panel, list, search_box, name_box, tags_box: canvas2d.Rectangle,
    slider_x, slider_y, slider_w: f32,
) {
    panel = {18, 18, 264, f32(height) - 36}
    inspector := material_lab_inspector_bounds(width, height)
    compact := inspector.height < 760
    search_box = {panel.x + 16, panel.y + 78, panel.width - 32, 38}
    list = {panel.x + 16, panel.y + 128, panel.width - 32, panel.height - 202}
    name_box = {inspector.x + 18, inspector.y + (compact ? 64 : 78), inspector.width - 36, compact ? 36 : 40}
    tags_box = {inspector.x + 18, inspector.y + (compact ? 119 : 146), inspector.width - 36, compact ? 30 : 34}
    slider_x = inspector.x + 118
    slider_y = inspector.y + (compact ? 221 : 252)
    slider_w = inspector.width - 198
    return
}

material_lab_inspector_bounds :: proc(width, height: i32) -> canvas2d.Rectangle {
    inspector_width := min(f32(350), max(f32(300), f32(width) * .25))
    return {f32(width) - inspector_width - 18, 18, inspector_width, f32(height) - 36}
}

material_lab_search_text :: proc() -> string {
    return string(material_lab.search[:min(int(material_lab.search_length), len(material_lab.search))])
}

material_lab_search_matches :: proc(name: string) -> bool {
    query := material_lab_search_text()
    if query == "" do return true
    if len(query) > len(name) do return false
    for start in 0 ..= len(name) - len(query) {
        matches := true
        for offset in 0 ..< len(query) {
            name_byte := name[start + offset]
            query_byte := query[offset]
            if name_byte >= 'A' && name_byte <= 'Z' do name_byte += 'a' - 'A'
            if query_byte >= 'A' && query_byte <= 'Z' do query_byte += 'a' - 'A'
            if name_byte != query_byte {
                matches = false
                break
            }
        }
        if matches do return true
    }
    return false
}

material_lab_material_matches_search :: proc(material: ^Material_Lab_Material) -> bool {
    return(
        material_lab_search_matches(material_lab_name(material)) ||
        material_lab_search_matches(material_lab_tags(material)) \
    )
}

material_lab_filtered_count :: proc() -> int {
    count := 0
    for index in 0 ..< int(material_lab.library.count) {
        if material_lab_material_matches_search(&material_lab.library.materials[index]) do count += 1
    }
    return count
}

material_lab_filtered_index :: proc(filtered_row: int) -> int {
    row := 0
    for index in 0 ..< int(material_lab.library.count) {
        if !material_lab_material_matches_search(&material_lab.library.materials[index]) do continue
        if row == filtered_row do return index
        row += 1
    }
    return -1
}

material_lab_selected_filtered_row :: proc() -> int {
    row := 0
    for index in 0 ..< int(material_lab.library.count) {
        if !material_lab_material_matches_search(&material_lab.library.materials[index]) do continue
        if index == material_lab.selected do return row
        row += 1
    }
    return -1
}

material_lab_search_append :: proc(text: string) {
    available := len(material_lab.search) - int(material_lab.search_length)
    count := min(len(text), available)
    if count <= 0 do return
    copy(material_lab.search[material_lab.search_length:], transmute([]u8)text[:count])
    material_lab.search_length += u8(count)
    material_lab.list_scroll_y = 0
}

material_lab_search_backspace :: proc() {
    if material_lab.search_length == 0 do return
    material_lab.search_length -= 1
    for material_lab.search_length > 0 && (material_lab.search[material_lab.search_length] & 0xc0) == 0x80 {
        material_lab.search_length -= 1
    }
    material_lab.search[material_lab.search_length] = 0
    material_lab.list_scroll_y = 0
}

material_lab_list_max_scroll :: proc(list: canvas2d.Rectangle) -> f32 {
    content_height := f32(material_lab_filtered_count()) * 34 + 6
    return max(content_height - list.height, 0)
}

material_lab_list_scrollbar_track :: proc(list: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {list.x + list.width - 8, list.y + 5, 4, list.height - 10}
}

material_lab_list_scrollbar_thumb :: proc(list: canvas2d.Rectangle) -> canvas2d.Rectangle {
    track := material_lab_list_scrollbar_track(list)
    content_height := max(f32(material_lab_filtered_count()) * 34 + 6, list.height)
    thumb_height := max(track.height * list.height / content_height, f32(28))
    travel := max(track.height - thumb_height, f32(1))
    maximum := material_lab_list_max_scroll(list)
    normalized := maximum > 0 ? clamp(material_lab.list_scroll_y / maximum, 0, 1) : f32(0)
    return {track.x - 3, track.y + travel * normalized, track.width + 6, thumb_height}
}

material_lab_list_reveal_selected :: proc(list: canvas2d.Rectangle) {
    filtered_row := material_lab_selected_filtered_row()
    if filtered_row < 0 do return
    row_height := f32(34)
    row_top := f32(filtered_row) * row_height
    row_bottom := row_top + row_height
    if row_top < material_lab.list_scroll_y {
        material_lab.list_scroll_y = row_top
    } else if row_bottom > material_lab.list_scroll_y + list.height {
        material_lab.list_scroll_y = row_bottom - list.height
    }
    material_lab.list_scroll_y = clamp(material_lab.list_scroll_y, 0, material_lab_list_max_scroll(list))
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
    width, height := canvas2d.GetScreenWidth(), canvas2d.GetScreenHeight()
    panel, list, search_box, name_box, tags_box, slider_x, slider_y, slider_w := material_lab_layout(width, height)
    inspector := material_lab_inspector_bounds(width, height)
    slider_stride := inspector.height < 760 ? f32(36) : f32(54)
    mouse := canvas2d.GetMousePosition()
    pressed := canvas2d.IsMouseButtonPressed(.LEFT)
    lighting_bounds := material_lab_lighting_bounds(width)
    viewport_input :=
        !canvas2d.CheckCollisionPointRec(mouse, panel) &&
        !canvas2d.CheckCollisionPointRec(mouse, inspector) &&
        !canvas2d.CheckCollisionPointRec(mouse, lighting_bounds)

    if viewport_input && canvas2d.IsMouseButtonDown(.RIGHT) {
        mouse_delta := canvas2d.GetMouseDelta()
        material_lab.orbit_yaw -= mouse_delta.x * .008
        material_lab.orbit_pitch = clamp(material_lab.orbit_pitch - mouse_delta.y * .006, -.55, 1.15)
        material_lab_update_camera(editor)
    }
    wheel := canvas2d.GetMouseWheelMove()
    if canvas2d.CheckCollisionPointRec(mouse, list) && math.abs(wheel) > .01 {
        material_lab.list_scroll_y = clamp(
            material_lab.list_scroll_y - wheel * 42,
            0,
            material_lab_list_max_scroll(list),
        )
    } else if viewport_input && math.abs(wheel) > .01 {
        if shift_key_down() {
            material_lab.lighting_minutes += wheel * 30
            atmosphere.set_world_minutes(&editor.atmosphere, material_lab.lighting_minutes)
        } else {
            material_lab.orbit_distance = clamp(material_lab.orbit_distance * f32(math.pow(.86, f64(wheel))), 3.4, 18)
            material_lab_update_camera(editor)
        }
    }

    lighting_track := canvas2d.Rectangle {
        lighting_bounds.x + 14,
        lighting_bounds.y + 35,
        lighting_bounds.width - 28,
        12,
    }
    if canvas2d.IsMouseButtonDown(.LEFT) && canvas2d.CheckCollisionPointRec(mouse, lighting_bounds) {
        normalized := clamp((mouse.x - lighting_track.x) / lighting_track.width, 0, 1)
        // Keep the useful daylight arc on one slider, from sunrise through sunset.
        material_lab.lighting_minutes = 6 * 60 + normalized * 12 * 60
        atmosphere.set_world_minutes(&editor.atmosphere, material_lab.lighting_minutes)
    }

    if material_lab.search_editing {
        _ = canvas2d.SetTextInputArea(search_box, int(material_lab.search_length))
        material_lab_search_append(canvas2d.GetTextInput())
        if canvas2d.IsKeyPressed(.BACKSPACE) do material_lab_search_backspace()
        if canvas2d.IsKeyPressed(.ENTER) do material_lab.search_editing = false
    } else if material_lab.tags_editing {
        material := material_lab_current()
        if material != nil {
            _ = canvas2d.SetTextInputArea(tags_box, int(material.tags_length))
            material_lab_append_tags(canvas2d.GetTextInput())
            if canvas2d.IsKeyPressed(.BACKSPACE) do material_lab_backspace_tags()
            if canvas2d.IsKeyPressed(.ENTER) do material_lab.tags_editing = false
        }
    } else if material_lab.name_editing {
        _ = canvas2d.SetTextInputArea(name_box, int(material_lab_current().name_length))
        material_lab_append_name(canvas2d.GetTextInput())
        if canvas2d.IsKeyPressed(.BACKSPACE) do material_lab_backspace_name()
        if canvas2d.IsKeyPressed(.ENTER) do material_lab.name_editing = false
    }

    row_height := f32(34)
    list_rows := list
    if material_lab_list_max_scroll(list) > 0 do list_rows.width -= 16
    if pressed && canvas2d.CheckCollisionPointRec(mouse, list_rows) {
        filtered_row := int((mouse.y - list.y + material_lab.list_scroll_y) / row_height)
        index := material_lab_filtered_index(filtered_row)
        if index >= 0 && index < int(material_lab.library.count) {
            material_lab.selected = index
            material_lab.name_editing = false
            material_lab.tags_editing = false
            material_lab_maps_load()
        }
    }

    maximum_scroll := material_lab_list_max_scroll(list)
    material_lab.list_scroll_y = clamp(material_lab.list_scroll_y, 0, maximum_scroll)
    scrollbar := material_lab_list_scrollbar_track(list)
    thumb := material_lab_list_scrollbar_thumb(list)
    if maximum_scroll > 0 && pressed && canvas2d.CheckCollisionPointRec(mouse, thumb) {
        material_lab.list_scroll_dragging = true
        material_lab.list_scroll_drag_offset = mouse.y - thumb.y
    } else if maximum_scroll > 0 &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, {scrollbar.x - 8, scrollbar.y, 20, scrollbar.height}) {
        travel := max(scrollbar.height - thumb.height, f32(1))
        normalized := clamp((mouse.y - scrollbar.y - thumb.height * .5) / travel, 0, 1)
        material_lab.list_scroll_y = normalized * maximum_scroll
        material_lab.list_scroll_dragging = true
        material_lab.list_scroll_drag_offset = thumb.height * .5
    }
    if material_lab.list_scroll_dragging {
        if canvas2d.IsMouseButtonDown(.LEFT) {
            thumb = material_lab_list_scrollbar_thumb(list)
            travel := max(scrollbar.height - thumb.height, f32(1))
            normalized := clamp((mouse.y - material_lab.list_scroll_drag_offset - scrollbar.y) / travel, 0, 1)
            material_lab.list_scroll_y = normalized * maximum_scroll
        } else {
            material_lab.list_scroll_dragging = false
        }
    }
    if pressed && canvas2d.CheckCollisionPointRec(mouse, search_box) {
        material_lab.search_editing = true
        material_lab.name_editing = false
        material_lab.tags_editing = false
    }
    if pressed && canvas2d.CheckCollisionPointRec(mouse, name_box) {
        material_lab.name_editing = true
        material_lab.search_editing = false
        material_lab.tags_editing = false
    }
    if pressed && canvas2d.CheckCollisionPointRec(mouse, tags_box) {
        material_lab.tags_editing = true
        material_lab.name_editing = false
        material_lab.search_editing = false
    }

    buttons_y := panel.y + panel.height - 54
    new_button := canvas2d.Rectangle{panel.x + 16, buttons_y, 92, 36}
    duplicate_button := canvas2d.Rectangle{panel.x + 116, buttons_y, panel.width - 132, 36}
    inspector_buttons_y := inspector.y + inspector.height - 54
    delete_button := canvas2d.Rectangle{inspector.x + 18, inspector_buttons_y, 74, 36}
    revert_button := canvas2d.Rectangle{inspector.x + inspector.width - 190, inspector_buttons_y, 82, 36}
    save_button := canvas2d.Rectangle{inspector.x + inspector.width - 100, inspector_buttons_y, 82, 36}
    if pressed && canvas2d.CheckCollisionPointRec(mouse, new_button) do material_lab_add(false)
    if pressed && canvas2d.CheckCollisionPointRec(mouse, duplicate_button) do material_lab_add(true)
    if pressed && canvas2d.CheckCollisionPointRec(mouse, delete_button) do material_lab_delete()
    if pressed &&
       (canvas2d.CheckCollisionPointRec(mouse, new_button) ||
               canvas2d.CheckCollisionPointRec(mouse, duplicate_button) ||
               canvas2d.CheckCollisionPointRec(mouse, delete_button)) {
        material_lab_list_reveal_selected(list)
    }
    if pressed && canvas2d.CheckCollisionPointRec(mouse, revert_button) {
        if material_lab_load() {
            material_lab.selected = min(material_lab.selected, int(material_lab.library.count) - 1)
            material_lab.dirty = false
            material_lab_maps_load()
            material_lab_list_reveal_selected(list)
            material_lab_status("CHANGES REVERTED")
        } else {
            material_lab_status("NO SAVED LIBRARY")
        }
    }
    if pressed && canvas2d.CheckCollisionPointRec(mouse, save_button) {
        if material_lab_save() {
            material_lab.dirty = false
            material_lab_status("LIBRARY SAVED")
        } else {
            material_lab_status("SAVE FAILED")
        }
    }

    if pressed {
        for index in 0 ..< MATERIAL_LAB_SLIDER_COUNT {
            bounds := canvas2d.Rectangle{slider_x, slider_y + f32(index) * slider_stride - 12, slider_w, 36}
            if canvas2d.CheckCollisionPointRec(mouse, bounds) {
                material_lab.dragging = index
                material_lab_set_slider(index, (mouse.x - slider_x) / slider_w)
                break
            }
        }
    }
    if canvas2d.IsMouseButtonDown(.LEFT) && material_lab.dragging >= 0 {
        material_lab_set_slider(material_lab.dragging, (mouse.x - slider_x) / slider_w)
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) do material_lab.dragging = -1
    if canvas2d.IsKeyPressed(.ESCAPE) {
        if material_lab.search_editing {
            material_lab.search_editing = false
        } else if material_lab.tags_editing {
            material_lab.tags_editing = false
        } else if material_lab.name_editing {
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

material_lab_button :: proc(bounds: canvas2d.Rectangle, label: cstring, accent: bool = false) {
    hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
    fill := accent ? canvas2d.Color{133, 91, 42, 255} : canvas2d.Color{34, 43, 43, 255}
    if hovered do fill = accent ? canvas2d.Color{161, 111, 51, 255} : canvas2d.Color{48, 59, 58, 255}
    canvas2d.DrawRectangleRounded(bounds, .20, 6, fill)
    canvas2d.DrawRectangleRoundedLinesEx(
        bounds,
        .20,
        6,
        1,
        accent ? canvas2d.Color{240, 194, 111, 255} : canvas2d.Color{102, 125, 121, 255},
    )
    size := ui_measure_text(.Label, label, .27)
    ui_draw_text(.Label, label, {bounds.x + (bounds.width - size.x) * .5, bounds.y + 10}, .27, {234, 231, 213, 255})
}

material_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel, list, search_box, name_box, tags_box, slider_x, slider_y, slider_w := material_lab_layout(width, height)
    inspector := material_lab_inspector_bounds(width, height)
    compact := inspector.height < 760
    slider_stride := compact ? f32(36) : f32(54)
    canvas2d.DrawRectangleRounded(panel, .035, 10, {15, 23, 24, 255})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .035, 10, 1, {74, 93, 91, 255})
    canvas2d.DrawRectangleRounded(inspector, .035, 10, {15, 23, 24, 255})
    canvas2d.DrawRectangleRoundedLinesEx(inspector, .035, 10, 1, {74, 93, 91, 255})
    lighting_bounds := material_lab_lighting_bounds(width)
    canvas2d.DrawRectangleRounded(lighting_bounds, .12, 8, {15, 23, 24, 230})
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
    light_track := canvas2d.Rectangle{lighting_bounds.x + 14, lighting_bounds.y + 39, lighting_bounds.width - 28, 7}
    canvas2d.DrawRectangleRounded(light_track, 1, 4, {48, 57, 57, 255})
    canvas2d.DrawRectangleRounded(
        {light_track.x, light_track.y, light_track.width * light_normalized, light_track.height},
        1,
        4,
        {240, 194, 111, 255},
    )
    canvas2d.DrawCircleV(
        {light_track.x + light_track.width * light_normalized, light_track.y + light_track.height * .5},
        7,
        {239, 232, 210, 255},
    )
    ui_draw_text(.Label, "MATERIALS", {panel.x + 16, panel.y + 18}, .42, {240, 194, 111, 255})
    ui_draw_text(
        .Data,
        fmt.ctprintf("%d IN LIBRARY", material_lab.library.count),
        {panel.x + 16, panel.y + 48},
        .16,
        {150, 169, 164, 255},
    )
    ui_draw_text(.Label, "MATERIAL INSPECTOR", {inspector.x + 18, inspector.y + 18}, .36, {240, 194, 111, 255})
    ui_draw_text(.Data, "NAME", {name_box.x, name_box.y - 18}, .15, {150, 169, 164, 255})

    canvas2d.DrawRectangleRounded(search_box, .14, 6, {8, 15, 16, 255})
    canvas2d.DrawRectangleRoundedLinesEx(
        search_box,
        .14,
        6,
        1,
        material_lab.search_editing ? canvas2d.Color{240, 194, 111, 255} : canvas2d.Color{74, 93, 91, 255},
    )
    search_text := material_lab_search_text()
    search_label :=
        search_text == "" ? "SEARCH MATERIALS" : fmt.ctprintf("%s%s", search_text, material_lab.search_editing && int(canvas2d.GetTime() * 2) % 2 == 0 ? "_" : "")
    search_text_size := ui_measure_text(.Data, search_label, .18)
    search_text_x := search_box.x + 10
    if material_lab.search_editing && search_text_size.x > search_box.width - 20 {
        search_text_x -= search_text_size.x - (search_box.width - 20)
    }
    canvas2d.BeginScissorMode({search_box.x + 2, search_box.y + 2, search_box.width - 4, search_box.height - 4})
    ui_draw_text(
        .Data,
        search_label,
        {search_text_x, search_box.y + 10},
        .18,
        search_text == "" ? canvas2d.Color{104, 121, 118, 255} : canvas2d.Color{232, 229, 211, 255},
    )
    canvas2d.EndScissorMode()

    canvas2d.DrawRectangleRounded(list, .035, 6, {9, 15, 16, 255})
    row_height := f32(34)
    canvas2d.BeginScissorMode(list)
    filtered_row := 0
    for index in 0 ..< int(material_lab.library.count) {
        if !material_lab_material_matches_search(&material_lab.library.materials[index]) do continue
        bounds := canvas2d.Rectangle {
            list.x + 4,
            list.y + f32(filtered_row) * row_height + 3 - material_lab.list_scroll_y,
            list.width - 16,
            row_height - 5,
        }
        filtered_row += 1
        if bounds.y + bounds.height < list.y || bounds.y > list.y + list.height do continue
        selected := material_lab.selected == index
        if selected || canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds) {
            canvas2d.DrawRectangleRounded(
                bounds,
                .16,
                5,
                selected ? canvas2d.Color{87, 66, 36, 255} : canvas2d.Color{28, 38, 38, 255},
            )
        }
        swatch := material_lab.library.materials[index].color
        canvas2d.DrawCircleV({bounds.x + 14, bounds.y + bounds.height * .5}, 6, {swatch[0], swatch[1], swatch[2], 255})
        ui_draw_text(
            .Label,
            fmt.ctprintf("%02d  %s", index + 1, material_lab_name(&material_lab.library.materials[index])),
            {bounds.x + 26, bounds.y + 9},
            .25,
            selected ? canvas2d.Color{247, 218, 157, 255} : canvas2d.Color{198, 207, 200, 255},
        )
    }
    if filtered_row == 0 {
        ui_draw_text(.Data, "NO MATCHES", {list.x + 12, list.y + 14}, .18, {104, 121, 118, 255})
    }
    canvas2d.EndScissorMode()
    if material_lab_list_max_scroll(list) > 0 {
        track := material_lab_list_scrollbar_track(list)
        thumb := material_lab_list_scrollbar_thumb(list)
        canvas2d.DrawRectangleRounded(track, 1, 4, {42, 53, 52, 255})
        canvas2d.DrawRectangleRounded(
            thumb,
            1,
            5,
            material_lab.list_scroll_dragging ? canvas2d.Color{240, 194, 111, 255} : canvas2d.Color{111, 130, 126, 255},
        )
    }

    canvas2d.DrawRectangleRounded(name_box, .14, 6, {8, 15, 16, 255})
    canvas2d.DrawRectangleRoundedLinesEx(
        name_box,
        .14,
        6,
        1,
        material_lab.name_editing ? canvas2d.Color{240, 194, 111, 255} : canvas2d.Color{74, 93, 91, 255},
    )
    name := material_lab_current() == nil ? "" : material_lab_name(material_lab_current())
    name_label := fmt.ctprintf(
        "%s%s",
        name,
        material_lab.name_editing && int(canvas2d.GetTime() * 2) % 2 == 0 ? "_" : "",
    )
    name_text_size := ui_measure_text(.Label, name_label, .31)
    name_text_x := name_box.x + 12
    if material_lab.name_editing && name_text_size.x > name_box.width - 24 {
        name_text_x -= name_text_size.x - (name_box.width - 24)
    }
    canvas2d.BeginScissorMode({name_box.x + 2, name_box.y + 2, name_box.width - 4, name_box.height - 4})
    ui_draw_text(.Label, name_label, {name_text_x, name_box.y + 12}, .31, {232, 229, 211, 255})
    canvas2d.EndScissorMode()

    canvas2d.DrawRectangleRounded(tags_box, .14, 6, {8, 15, 16, 255})
    canvas2d.DrawRectangleRoundedLinesEx(
        tags_box,
        .14,
        6,
        1,
        material_lab.tags_editing ? canvas2d.Color{240, 194, 111, 255} : canvas2d.Color{74, 93, 91, 255},
    )
    tags := material_lab_tags(material_lab_current())
    ui_draw_text(.Data, "TAGS", {tags_box.x, tags_box.y - 17}, .15, {150, 169, 164, 255})
    tags_label :=
        tags == "" ? "Add comma-separated tags" : fmt.ctprintf("%s%s", tags, material_lab.tags_editing && int(canvas2d.GetTime() * 2) % 2 == 0 ? "_" : "")
    tags_text_size := ui_measure_text(.Data, tags_label, .15)
    tags_text_x := tags_box.x + 10
    if material_lab.tags_editing && tags_text_size.x > tags_box.width - 20 {
        tags_text_x -= tags_text_size.x - (tags_box.width - 20)
    }
    canvas2d.BeginScissorMode({tags_box.x + 2, tags_box.y + 2, tags_box.width - 4, tags_box.height - 4})
    ui_draw_text(
        .Data,
        tags_label,
        {tags_text_x, tags_box.y + 8},
        .15,
        tags == "" ? canvas2d.Color{104, 121, 118, 255} : canvas2d.Color{198, 207, 200, 255},
    )
    canvas2d.EndScissorMode()

    labels := [?]cstring{"RED", "GREEN", "BLUE", "METALLIC", "ROUGHNESS"}
    colors := [?]canvas2d.Color {
        {198, 69, 55, 255},
        {70, 164, 102, 255},
        {65, 126, 190, 255},
        {210, 181, 119, 255},
        {164, 179, 174, 255},
    }
    for label, index in labels {
        y := slider_y + f32(index) * slider_stride
        value := material_lab_slider_value(index)
        ui_draw_text(.Label, label, {inspector.x + 18, y - 7}, .24, {179, 190, 185, 255})
        canvas2d.DrawRectangleRounded({slider_x, y, slider_w, 9}, 1, 4, {48, 57, 57, 255})
        canvas2d.DrawRectangleRounded({slider_x, y, slider_w * value, 9}, 1, 4, colors[index])
        canvas2d.DrawCircleV({slider_x + slider_w * value, y + 4.5}, 8, {239, 232, 210, 255})
        value_text := index < 3 ? fmt.ctprintf("%d", int(value * 255 + .5)) : fmt.ctprintf("%.2f", value)
        value_bounds := canvas2d.Rectangle{inspector.x + inspector.width - 62, y - 13, 44, 28}
        canvas2d.DrawRectangleRounded(value_bounds, .18, 5, {8, 15, 16, 255})
        ui_draw_text(.Data, value_text, {value_bounds.x + 7, value_bounds.y + 8}, .18, {205, 211, 202, 255})
    }

    material := material_lab_current()
    if material != nil {
        base_color_y := inspector.y + (compact ? f32(161) : f32(198))
        ui_draw_text(.Data, "BASE COLOR", {inspector.x + 18, base_color_y}, .15, {150, 169, 164, 255})
        swatch_bounds := canvas2d.Rectangle {
            inspector.x + 118,
            base_color_y - 7,
            inspector.width - 136,
            compact ? 32 : 36,
        }
        canvas2d.DrawRectangleRounded(
            swatch_bounds,
            .16,
            6,
            {material.color[0], material.color[1], material.color[2], 255},
        )
        contrast :=
            (int(material.color[0]) + int(material.color[1]) + int(material.color[2])) > 390 ? canvas2d.Color{18, 25, 25, 255} : canvas2d.Color{242, 239, 221, 255}
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
            {swatch_bounds.x + 10, swatch_bounds.y + 12},
            .18,
            contrast,
        )
        maps_y :=
            compact ? min(inspector.y + 415, inspector.y + inspector.height - 176) : min(inspector.y + 538, inspector.y + inspector.height - 176)
        ui_draw_text(.Data, "TEXTURE MAPS", {inspector.x + 18, maps_y - 20}, .15, {150, 169, 164, 255})
        for map_name, index in MATERIAL_LAB_MAP_NAMES {
            attached := material_lab_map_path(material, Material_Lab_Map_Kind(index)) != ""
            map_bounds := canvas2d.Rectangle{inspector.x + 18, maps_y + f32(index) * 30, inspector.width - 36, 25}
            canvas2d.DrawRectangleRounded(map_bounds, .12, 5, {24, 33, 33, 255})
            ui_draw_text(
                .Data,
                fmt.ctprintf("%s", map_name),
                {map_bounds.x + 10, map_bounds.y + 8},
                .16,
                attached ? canvas2d.Color{240, 194, 111, 255} : canvas2d.Color{116, 133, 130, 255},
            )
            status: cstring = attached ? "ATTACHED" : "EMPTY"
            status_size := ui_measure_text(.Data, status, .14)
            ui_draw_text(
                .Data,
                status,
                {map_bounds.x + map_bounds.width - status_size.x - 10, map_bounds.y + 9},
                .14,
                attached ? canvas2d.Color{170, 196, 154, 255} : canvas2d.Color{104, 121, 118, 255},
            )
        }
    }

    buttons_y := panel.y + panel.height - 54
    material_lab_button({panel.x + 16, buttons_y, 92, 36}, "+ NEW")
    material_lab_button({panel.x + 116, buttons_y, panel.width - 132, 36}, "DUPLICATE")
    inspector_buttons_y := inspector.y + inspector.height - 54
    material_lab_button({inspector.x + 18, inspector_buttons_y, 74, 36}, "DELETE")
    material_lab_button({inspector.x + inspector.width - 190, inspector_buttons_y, 82, 36}, "REVERT")
    material_lab_button(
        {inspector.x + inspector.width - 100, inspector_buttons_y, 82, 36},
        material_lab.dirty ? "SAVE *" : "SAVED",
        material_lab.dirty,
    )
    if material_lab.status != nil && canvas2d.GetTime() < material_lab.status_until {
        ui_draw_text(.Data, material_lab.status, {inspector.x + 18, inspector.y + 48}, .18, {240, 194, 111, 255})
    }
    help: cstring = "RIGHT-DRAG  ORBIT   WHEEL  ZOOM   SHIFT+WHEEL  LIGHT   ESC  EXIT"
    help_size := ui_measure_text(.Data, help, .20)
    preview_left := panel.x + panel.width
    preview_width := inspector.x - preview_left
    ui_draw_text(
        .Data,
        help,
        {preview_left + (preview_width - help_size.x) * .5, f32(height) - 27},
        .20,
        {190, 198, 190, 255},
    )
}
