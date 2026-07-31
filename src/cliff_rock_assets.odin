package main

import gltf "zelda_engine:gltf"

CLIFF_ROCK_ASSET_COUNT :: 10
CLIFF_ROCK_ASSET_PATHS := [CLIFF_ROCK_ASSET_COUNT]string {
    "assets/models/cliff-rocks/cliff-rock-01-buttress.glb",
    "assets/models/cliff-rocks/cliff-rock-02-wide-shelf.glb",
    "assets/models/cliff-rocks/cliff-rock-03-tall-pillar.glb",
    "assets/models/cliff-rocks/cliff-rock-04-leaning-slab.glb",
    "assets/models/cliff-rocks/cliff-rock-05-corner-wedge.glb",
    "assets/models/cliff-rocks/cliff-rock-06-low-boulder.glb",
    "assets/models/cliff-rocks/cliff-rock-07-overhang.glb",
    "assets/models/cliff-rocks/cliff-rock-08-narrow-fin.glb",
    "assets/models/cliff-rocks/cliff-rock-09-terrace.glb",
    "assets/models/cliff-rocks/cliff-rock-10-hero-stack.glb",
}

Cliff_Rock_Assets :: struct {
    meshes: [CLIFF_ROCK_ASSET_COUNT]gltf.Glb_Mesh,
    ready:  [CLIFF_ROCK_ASSET_COUNT]bool,
}

cliff_rock_assets: Cliff_Rock_Assets

cliff_rock_assets_init :: proc() {
    for path, index in CLIFF_ROCK_ASSET_PATHS {
        mesh, ready := gltf.glb_load(path)
        cliff_rock_assets.meshes[index] = mesh
        cliff_rock_assets.ready[index] = ready
    }
}

cliff_rock_assets_destroy :: proc() {
    for &mesh, index in cliff_rock_assets.meshes {
        gltf.glb_mesh_destroy(&mesh)
        cliff_rock_assets.ready[index] = false
    }
}
