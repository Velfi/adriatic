package main

import plant_assets "../packages/plant_assets"

plant_asset_compile_cli :: proc(args: []string) -> bool {
    return plant_assets.plant_asset_compile_cli(args)
}
