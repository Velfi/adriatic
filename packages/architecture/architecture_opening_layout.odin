package architecture
import buildings "../buildings"
import plants "../plants"
import terrain "../terrain"
import "core:math"
architecture_opening_layout :: proc(
    structure: terrain.Structure,
    mass_index: int,
    primary_mass_index: int,
) -> Opening_Layout {
    layout: Opening_Layout
    footprint := architecture_footprint(structure)
    if mass_index < 0 || mass_index >= footprint.count do return layout
    mass := footprint.masses[mass_index]
    wall_height := max(f32(0), structure.height * mass.height_scale)
    if wall_height < ARCHITECTURE_MIN_OPENING_WALL_HEIGHT do return layout
    identity := architecture_resolve_legacy_identity(structure)
    profile := facade_profile(identity.archetype)
    farmstead_work_range :=
        identity.archetype == .Farmstead &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 20 &&
        structure.depth >= 18 &&
        structure.seed % 5 == 0
    if farmstead_work_range {
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 0,
            side_bays_max     = 1,
            window_width_min  = .80,
            window_width_max  = 1.10,
            window_height_min = 1.00,
            window_height_max = 1.40,
            opening_ratio_min = .03,
            opening_ratio_max = .08,
            rows_max          = 2,
            blank_sides       = true,
        }
    }
    shop_stock_range :=
        identity.archetype == .Shop_House &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 16 &&
        structure.depth >= 14 &&
        structure.seed % 4 == 0
    if shop_stock_range {
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 0,
            side_bays_max     = 1,
            window_width_min  = .75,
            window_width_max  = 1.05,
            window_height_min = .85,
            window_height_max = 1.25,
            opening_ratio_min = .025,
            opening_ratio_max = .07,
            rows_max          = 2,
            blank_sides       = true,
        }
    }
    post_sorting_range := identity.archetype == .Post_Office && mass_index > 0
    if post_sorting_range {
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 0,
            side_bays_max     = 1,
            window_width_min  = .80,
            window_width_max  = 1.05,
            window_height_min = .95,
            window_height_max = 1.30,
            opening_ratio_min = .025,
            opening_ratio_max = .07,
            rows_max          = 2,
            blank_sides       = true,
        }
    }
    clinic_ward_range := identity.archetype == .Clinic && mass_index > 0
    if clinic_ward_range {
        profile = {
            front_bays_min    = 2,
            front_bays_max    = 3,
            rear_bays_min     = 2,
            rear_bays_max     = 3,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.20,
            window_width_max  = 1.50,
            window_height_min = 1.60,
            window_height_max = 2.00,
            opening_ratio_min = .10,
            opening_ratio_max = .18,
            rows_max          = 3,
        }
    }
    fortress_tower := identity.archetype == .Fortress_Gate && footprint.count == 3 && mass_index < 2
    if fortress_tower {
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 1,
            rear_bays_min     = 1,
            rear_bays_max     = 1,
            side_bays_min     = 1,
            side_bays_max     = 1,
            window_width_min  = .38,
            window_width_max  = .55,
            window_height_min = 1.10,
            window_height_max = 1.60,
            opening_ratio_min = 0,
            opening_ratio_max = .035,
            rows_max          = 3,
            service           = true,
        }
    }
    fortress_guard_range := identity.archetype == .Fortress_Gate && footprint.count == 3 && mass_index == 2
    if fortress_guard_range {
        profile.rear_bays_min = 1
        profile.rear_bays_max = max(profile.rear_bays_max, 2)
    }
    bell_tower := (identity.archetype == .Campanile || identity.archetype == .Cycladic_Bell) && mass_index == 0
    if bell_tower {
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 1,
            rear_bays_min     = 1,
            rear_bays_max     = 1,
            side_bays_min     = 1,
            side_bays_max     = 1,
            window_width_min  = .50,
            window_width_max  = .75,
            window_height_min = 1.10,
            window_height_max = 1.70,
            opening_ratio_min = 0,
            opening_ratio_max = .045,
            rows_max          = 4,
            service           = true,
        }
    }
    mill_tower := identity.archetype == .Mill && footprint.count == 2 && mass_index == 1
    if mill_tower {
        profile = {
            front_bays_min    = 0,
            front_bays_max    = 0,
            rear_bays_min     = 0,
            rear_bays_max     = 0,
            side_bays_min     = 0,
            side_bays_max     = 0,
            window_width_min  = .55,
            window_width_max  = .80,
            window_height_min = .90,
            window_height_max = 1.30,
            opening_ratio_min = 0,
            opening_ratio_max = .04,
            rows_max          = 2,
            service           = true,
        }
    }
    barn_range := identity.archetype == .Barn_Granary
    if barn_range {
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 1,
            window_width_min  = .48,
            window_width_max  = .82,
            window_height_min = .55,
            window_height_max = .95,
            opening_ratio_min = .01,
            opening_ratio_max = .06,
            rows_max          = 1,
            service           = true,
        }
    }
    workshop_daylight := identity.archetype == .Workshop
    if workshop_daylight {
        profile = {
            front_bays_min    = 2,
            front_bays_max    = 4,
            rear_bays_min     = 1,
            rear_bays_max     = 3,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.20,
            window_width_max  = 1.80,
            window_height_min = 1.10,
            window_height_max = 1.60,
            opening_ratio_min = .025,
            opening_ratio_max = .09,
            rows_max          = 1,
            service           = true,
        }
    }
    fishery_work_hall := identity.archetype == .Fishery && mass_index == 0
    if fishery_work_hall {
        profile = {
            front_bays_min    = 2,
            front_bays_max    = 3,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.00,
            window_width_max  = 1.45,
            window_height_min = 1.00,
            window_height_max = 1.50,
            opening_ratio_min = .02,
            opening_ratio_max = .08,
            rows_max          = 1,
            service           = true,
        }
    }
    storehouse_high_vents := identity.archetype == .Storehouse
    if storehouse_high_vents {
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 3,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = .70,
            window_width_max  = .95,
            window_height_min = .70,
            window_height_max = 1.10,
            opening_ratio_min = .01,
            opening_ratio_max = .05,
            rows_max          = 1,
            service           = true,
        }
    }
    harbor_dispatch_range := identity.archetype == .Harbor_Office && footprint.count == 3 && mass_index == 1
    harbor_service_range := identity.archetype == .Harbor_Office && footprint.count == 3 && mass_index == 2
    if harbor_service_range {
        profile = facade_profile(.Storehouse)
    }
    habitable := buildings.is_habitable(identity.archetype) && !harbor_service_range
    occupied_secondary_daylight := habitable || identity.archetype == .Post_Office
    storehouse_loading_range :=
        identity.archetype == .Storehouse &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 20 &&
        structure.depth >= 16 &&
        structure.seed % 8 == 0
    fishery_smokehouse_range :=
        identity.archetype == .Fishery &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 18 &&
        structure.depth >= 14 &&
        structure.seed % 4 == 0
    market_loading_range :=
        identity.archetype == .Market_Hall &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 22 &&
        structure.depth >= 18
    market_basilica_aisle := identity.archetype == .Market_Hall && footprint.count == 3 && mass_index > 0
    market_basilica_nave := identity.archetype == .Market_Hall && footprint.count == 3 && mass_index == 0
    if market_basilica_aisle {
        profile = {
            front_bays_min    = 2,
            front_bays_max    = 3,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.20,
            window_width_max  = 1.60,
            window_height_min = 1.20,
            window_height_max = 1.70,
            opening_ratio_min = .03,
            opening_ratio_max = .08,
            rows_max          = 1,
        }
    }
    monastery_cloister_range := identity.archetype == .Monastery && footprint.count == 3 && mass_index == 0
    primary_mass := mass_index == primary_mass_index
    faces := [4]Face{.Front, .Rear, .Left, .Right}
    mixed_use_apartment_face := (structure.seed >> 2) & 1 == 0 ? Face.Left : Face.Right
    if identity.archetype == .Mixed_Use_Dwelling && footprint.count == 2 {
        mixed_use_apartment_face = footprint.masses[1].local_x < 0 ? Face.Right : Face.Left
    }
    architecture_opening_layout_add_faces(
        &layout,
        {
            structure = structure,
            footprint = footprint,
            mass = mass,
            identity = identity,
            profile = profile,
            wall_height = wall_height,
            mass_index = mass_index,
            farmstead_work_range = farmstead_work_range,
            shop_stock_range = shop_stock_range,
            post_sorting_range = post_sorting_range,
            clinic_ward_range = clinic_ward_range,
            fortress_tower = fortress_tower,
            fortress_guard_range = fortress_guard_range,
            bell_tower = bell_tower,
            mill_tower = mill_tower,
            barn_range = barn_range,
            workshop_daylight = workshop_daylight,
            fishery_work_hall = fishery_work_hall,
            storehouse_high_vents = storehouse_high_vents,
            harbor_dispatch_range = harbor_dispatch_range,
            harbor_service_range = harbor_service_range,
            habitable = habitable,
            occupied_secondary_daylight = occupied_secondary_daylight,
            storehouse_loading_range = storehouse_loading_range,
            fishery_smokehouse_range = fishery_smokehouse_range,
            market_loading_range = market_loading_range,
            market_basilica_aisle = market_basilica_aisle,
            market_basilica_nave = market_basilica_nave,
            monastery_cloister_range = monastery_cloister_range,
            primary_mass = primary_mass,
            mixed_use_apartment_face = mixed_use_apartment_face,
        },
    )
    architecture_opening_layout_finalize(
        &layout,
        {
            structure = structure,
            footprint = footprint,
            mass = mass,
            identity = identity,
            profile = profile,
            wall_height = wall_height,
            mass_index = mass_index,
            farmstead_work_range = farmstead_work_range,
            shop_stock_range = shop_stock_range,
            post_sorting_range = post_sorting_range,
            clinic_ward_range = clinic_ward_range,
            fortress_tower = fortress_tower,
            fortress_guard_range = fortress_guard_range,
            bell_tower = bell_tower,
            mill_tower = mill_tower,
            barn_range = barn_range,
            workshop_daylight = workshop_daylight,
            fishery_work_hall = fishery_work_hall,
            storehouse_high_vents = storehouse_high_vents,
            harbor_dispatch_range = harbor_dispatch_range,
            harbor_service_range = harbor_service_range,
            habitable = habitable,
            occupied_secondary_daylight = occupied_secondary_daylight,
            storehouse_loading_range = storehouse_loading_range,
            fishery_smokehouse_range = fishery_smokehouse_range,
            market_loading_range = market_loading_range,
            market_basilica_aisle = market_basilica_aisle,
            market_basilica_nave = market_basilica_nave,
            monastery_cloister_range = monastery_cloister_range,
            primary_mass = primary_mass,
            mixed_use_apartment_face = mixed_use_apartment_face,
        },
    )
    opening_layout_reindex_window_columns(&layout)
    return layout
}
