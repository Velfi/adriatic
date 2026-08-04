package main

import plant_assets "../../packages/plant_assets"
import "core:os"

main :: proc() {
    args := make([dynamic]string, 0, len(os.args) + 1)
    defer delete(args)
    append(&args, os.args[0], "plant-compile")
    if len(os.args) > 1 do append(&args, ..os.args[1:])
    if !plant_assets.plant_asset_compile_cli(args[:]) do os.exit(1)
}
