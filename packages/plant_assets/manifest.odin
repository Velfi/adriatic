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

plant_asset_manifest_valid :: proc() -> bool {
    manifest := PLANT_ASSET_MANIFEST
    for request, index in manifest {
        if request.habit != .Free_Standing || plants.default_habit(request.species) != .Free_Standing do return false
        for previous in 0 ..< index {
            if plant_asset_source_key(request) == plant_asset_source_key(manifest[previous]) do return false
        }
    }
    return true
}
