package plant_assets

import plants "../plants"

// Curated, support-independent base variants. Support-routed climbers are
// intentionally absent: their topology remains runtime-generated from the
// supplied wall, trellis, axes, and exclusions.
PLANT_ASSET_MANIFEST :: [?]Plant_Asset_Request {
    {species = .Olive, seed = 1000, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Italian_Cypress, seed = 1001, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Fig, seed = 1003, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Lemon, seed = 1004, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Pomegranate, seed = 1005, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Almond, seed = 1006, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Oleander, seed = 1007, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Rosemary, seed = 1009, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Stone_Pine, seed = 1010, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Bay_Laurel, seed = 1011, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Carob, seed = 1012, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Strawberry_Tree, seed = 1013, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Myrtle, seed = 1014, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Mastic, seed = 1015, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Lavender, seed = 1016, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Thyme, seed = 1017, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Sage, seed = 1018, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Prickly_Pear, seed = 1019, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Pelargonium, seed = 1020, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Hydrangea_Bush, seed = 1023, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Hydrangea_Tree, seed = 1024, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Agapanthus, seed = 1025, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Holm_Oak, seed = 1027, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Oriental_Plane, seed = 1028, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .European_Hackberry, seed = 1029, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .White_Poplar, seed = 1030, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Golden_Barrel, seed = 1031, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Agave, seed = 1032, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Aloe, seed = 1033, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Aeonium, seed = 1034, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Echeveria, seed = 1035, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Jade_Plant, seed = 1036, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Stonecrop, seed = 1037, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Blue_Chalk_Sticks, seed = 1038, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
    {species = .Golden_Torch_Cactus, seed = 1039, maturity_step = PLANT_MATURITY_STEPS, habit = .Free_Standing},
}

// Returns every support-independent request whose topology is selected from a
// bounded production set. The catalog references above are reviewed visual
// anchors. Residence pots and airport planters are the two production call
// sites whose generation keys are finite; settlement plans, patios, farms,
// cemeteries, and groves derive seeds from world data and intentionally use the
// runtime compiler.
plant_asset_manifest_requests :: proc(allocator := context.allocator) -> [dynamic]Plant_Asset_Request {
    result := make([dynamic]Plant_Asset_Request, 0, len(PLANT_ASSET_MANIFEST) + 72, allocator)
    for request in PLANT_ASSET_MANIFEST do append(&result, request)

    for bounded_seed in 0 ..< 32 {
        species := bounded_seed & 3 == 0 ? plants.Species.Agapanthus : .Pelargonium
        for side in ([2]int{-1, 1}) {
            seed := u64(bounded_seed) ~ u64(side + 1) << 8 ~ 0x5245535f504f54
            append(&result, Plant_Asset_Request {
                species = species,
                seed = seed,
                maturity_step = 4, // world_renderer_architecture_entry_props: .86
                habit = .Free_Standing,
            })
        }
    }

    for sign_key in ([2]u64{0x100, 0x200}) {
        for planter_index in 0 ..< 4 {
            append(&result, Plant_Asset_Request {
                species = planter_index & 1 == 0 ? .Oleander : .Lavender,
                seed = u64(0xa17c_ade0) ~ u64(planter_index) ~ sign_key,
                maturity_step = 4, // world_renderer_characters_signs: .82
                habit = .Free_Standing,
            })
        }
    }
    return result
}

plant_asset_manifest_valid :: proc() -> bool {
    manifest := plant_asset_manifest_requests(context.temp_allocator)
    for request, index in manifest {
        if request.habit != .Free_Standing || plants.default_habit(request.species) != .Free_Standing do return false
        for previous in 0 ..< index {
            if plant_asset_source_key(request) == plant_asset_source_key(manifest[previous]) do return false
        }
    }
    return true
}
