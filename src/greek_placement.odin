package main

import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:os"
import "core:strings"
import rl "zelda_engine:canvas2d"
import gltf "zelda_engine:gltf"

GREEK_ASSET_CAPACITY :: 8
GREEK_PLACEMENT_CAPACITY :: 64

Greek_Asset :: struct {
    name:  cstring,
    path:  string,
    mesh:  gltf.Glb_Mesh,
    color: rl.Color,
    ready: bool,
}

Greek_Placement :: struct {
    asset_index: int,
    x, z:        f32,
    base_y:      f32,
    rotation:    f32,
    scale:       f32,
}

greek_asset_init :: proc(editor: ^Editor) {
    if editor == nil do return
    paths := [GREEK_ASSET_CAPACITY]string {
        "assets/greek/GreekDoric_preview.glb",
        "assets/greek/MycenaeanPalace_preview.glb",
        "assets/greek/GreekTheater_preview.glb",
        "assets/greek/GreekAcropolis_preview.glb",
        "assets/greek/GreekAgoraStoa_preview.glb",
        "assets/greek/GreekTemple_Ionic_preview.glb",
        "assets/greek/GreekTombTholos_preview.glb",
        "assets/greek/AncientGreek_Settlement_preview.glb",
    }
    names := [GREEK_ASSET_CAPACITY]cstring {
        "DORIC TEMPLE",
        "MYCENAEAN PALACE",
        "GREEK THEATER",
        "ACROPOLIS FORT",
        "AGORA STOA",
        "IONIC TEMPLE",
        "TOMB / THOLOS",
        "GREEK SETTLEMENT",
    }
    colors := [GREEK_ASSET_CAPACITY]rl.Color {
        {224, 219, 196, 255},
        {192, 181, 153, 255},
        {211, 196, 169, 255},
        {170, 169, 155, 255},
        {205, 190, 164, 255},
        {226, 216, 190, 255},
        {182, 171, 151, 255},
        {200, 193, 175, 255},
    }
    editor.greek_asset_count = 0
    for index in 0 ..< GREEK_ASSET_CAPACITY {
        mesh, ready := gltf.glb_load(paths[index])
        if !ready {
            if working_dir, err := os.get_working_directory(context.temp_allocator); err == nil {
                absolute_path := strings.concatenate({working_dir, "/", paths[index]}, context.temp_allocator)
                mesh, ready = gltf.glb_load(absolute_path)
            }
        }
        if !ready {
            // The desktop build can be launched from Finder, where the
            // process working directory is not the repository root.
            project_path := strings.concatenate(
                {"/Users/zelda/Documents/adriatic/", paths[index]},
                context.temp_allocator,
            )
            mesh, ready = gltf.glb_load(project_path)
        }
        editor.greek_assets[index] = {
            name  = names[index],
            path  = paths[index],
            mesh  = mesh,
            color = colors[index],
            ready = ready,
        }
        if ready do editor.greek_asset_count += 1
    }
    editor.greek_asset_selected = 0
    editor.greek_asset_rotation = 0
    editor.greek_asset_scale = 1
    editor.greek_placement_count = 0
    editor.greek_placement_selected = -1
}

greek_asset_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    for &asset in editor.greek_assets {
        gltf.glb_mesh_destroy(&asset.mesh)
        asset.ready = false
    }
    editor.greek_asset_count = 0
}

greek_asset_selected_ready :: proc(editor: ^Editor) -> bool {
    return(
        editor != nil &&
        editor.greek_asset_selected >= 0 &&
        editor.greek_asset_selected < GREEK_ASSET_CAPACITY &&
        editor.greek_assets[editor.greek_asset_selected].ready \
    )
}

greek_placement_remove_selected :: proc(editor: ^Editor) {
    if editor == nil || editor.greek_placement_selected < 0 || editor.greek_placement_selected >= editor.greek_placement_count do return
    index := editor.greek_placement_selected
    for move in index + 1 ..< editor.greek_placement_count {
        editor.greek_placements[move - 1] = editor.greek_placements[move]
    }
    editor.greek_placement_count -= 1
    editor.greek_placement_selected = -1
    editor.project.revision += 1
}

greek_placement_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.greek_placement_mode do return
    if rl.IsKeyPressed(.BACKSPACE) {
        greek_placement_remove_selected(editor)
        return
    }
    if !cursor_hit || !greek_asset_selected_ready(editor) do return
    if rl.IsMouseButtonPressed(.LEFT) && editor.greek_placement_count < GREEK_PLACEMENT_CAPACITY {
        base_y := terrain.sample_height(&editor.project, 0, world_x, world_z)
        editor.greek_placements[editor.greek_placement_count] = {
            asset_index = editor.greek_asset_selected,
            x           = world_x,
            z           = world_z,
            base_y      = base_y,
            rotation    = editor.greek_asset_rotation,
            scale       = editor.greek_asset_scale,
        }
        editor.greek_placement_selected = editor.greek_placement_count
        editor.greek_placement_count += 1
        editor.project.revision += 1
    }
}

greek_asset_local_to_world :: proc(
    asset: Greek_Asset,
    placement: Greek_Placement,
    vertex: gltf.Vec3,
) -> third_person.Vec3 {
    c := f32(math.cos(f64(placement.rotation)))
    s := f32(math.sin(f64(placement.rotation)))
    scaled_x, scaled_y, scaled_z := vertex.x * placement.scale, vertex.y * placement.scale, vertex.z * placement.scale
    return third_person.Vec3 {
        placement.x + scaled_x * c - scaled_z * s,
        placement.base_y + (scaled_y - asset.mesh.min.y * placement.scale),
        placement.z + scaled_x * s + scaled_z * c,
    }
}
