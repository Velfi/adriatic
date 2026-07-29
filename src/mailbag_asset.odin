package main

import "core:os"
import "core:strings"
import gltf "zelda_engine:gltf"

MAILBAG_POUCH_ASSET_PATH :: "assets/models/mouse-mailbag-pouch.glb"

Mailbag_Pouch_Asset :: struct {
    mesh:  gltf.Glb_Mesh,
    ready: bool,
}

mailbag_pouch_asset_init :: proc(editor: ^Editor) {
    if editor == nil do return
    mesh, ready := gltf.glb_load(MAILBAG_POUCH_ASSET_PATH)
    if !ready {
        if working_dir, err := os.get_working_directory(context.temp_allocator); err == nil {
            absolute_path := strings.concatenate({working_dir, "/", MAILBAG_POUCH_ASSET_PATH}, context.temp_allocator)
            mesh, ready = gltf.glb_load(absolute_path)
        }
    }
    if !ready {
        project_path := strings.concatenate(
            {"/Users/zelda/Documents/adriatic/", MAILBAG_POUCH_ASSET_PATH},
            context.temp_allocator,
        )
        mesh, ready = gltf.glb_load(project_path)
    }
    editor.mailbag_pouch_asset = {
        mesh  = mesh,
        ready = ready,
    }
}

mailbag_pouch_asset_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    gltf.glb_mesh_destroy(&editor.mailbag_pouch_asset.mesh)
    editor.mailbag_pouch_asset.ready = false
}
