package main

import atmosphere "../packages/atmosphere"
import branch_mesh "../packages/branch_mesh"
import flower_mesh "../packages/flower_mesh"
import leaf_mesh "../packages/leaf_mesh"
import lsystem "../packages/lsystem"
import plants "../packages/plants"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strconv"
import rl "zelda_engine:canvas2d"

plant_generator_seed := u64(73)
plant_generator_maturity := f32(1)
plant_generator_detail := plants.Detail_Level.Near
plant_generator_isolated := -1
plant_generator_results: [plants.SPECIES_COUNT]plants.Generate_Result
plant_generator_ready: [plants.SPECIES_COUNT]bool
plant_generator_exclusions: [3]plants.Rect
plant_generator_leaf_meshes: [plants.SPECIES_COUNT][4]leaf_mesh.Mesh
plant_generator_leaf_mesh_ready: [plants.SPECIES_COUNT][4]bool
plant_generator_flower_meshes: [plants.SPECIES_COUNT][4]flower_mesh.Mesh
plant_generator_flower_mesh_ready: [plants.SPECIES_COUNT][4]bool
plant_generator_fruit_meshes: [plants.SPECIES_COUNT][4]flower_mesh.Mesh
plant_generator_fruit_mesh_ready: [plants.SPECIES_COUNT][4]bool
plant_generator_branch_meshes: [plants.SPECIES_COUNT]branch_mesh.Mesh
plant_generator_branch_mesh_ready: [plants.SPECIES_COUNT]bool
plant_generator_wind_base: third_person.Vec3
plant_generator_wind_height: f32
plant_generator_wind_compliance: f32
plant_generator_camera_close := false
plant_generator_camera_base := false

plant_generator_species_slug :: proc(species: plants.Species) -> string {
    #partial switch species {
    case .Olive:
        return "olive"
    case .Italian_Cypress:
        return "cypress"
    case .Grapevine:
        return "grapevine"
    case .Fig:
        return "fig"
    case .Lemon:
        return "lemon"
    case .Pomegranate:
        return "pomegranate"
    case .Almond:
        return "almond"
    case .Oleander:
        return "oleander"
    case .Bougainvillea:
        return "bougainvillea"
    case .Rosemary:
        return "rosemary"
    case .Stone_Pine:
        return "stone-pine"
    case .Bay_Laurel:
        return "bay-laurel"
    case .Carob:
        return "carob"
    case .Strawberry_Tree:
        return "strawberry-tree"
    case .Myrtle:
        return "myrtle"
    case .Mastic:
        return "mastic"
    case .Lavender:
        return "lavender"
    case .Thyme:
        return "thyme"
    case .Sage:
        return "sage"
    case .Prickly_Pear:
        return "prickly-pear"
    case .Pelargonium:
        return "pelargonium"
    }
    return ""
}

plant_generator_find_species :: proc(name: string) -> int {
    for index in 0 ..< plants.SPECIES_COUNT {
        if plant_generator_species_slug(plants.Species(index)) == name do return index
    }
    return -1
}

plant_generator_destroy :: proc() {
    for index in 0 ..< plants.SPECIES_COUNT {
        if plant_generator_ready[index] {
            plants.destroy(&plant_generator_results[index])
            plant_generator_ready[index] = false
        }
        for variant in 0 ..< len(plant_generator_leaf_mesh_ready[index]) {
            plant_generator_leaf_mesh_ready[index][variant] = false
        }
        for stage in 0 ..< 4 {
            plant_generator_flower_mesh_ready[index][stage] = false
            plant_generator_fruit_mesh_ready[index][stage] = false
        }
        if plant_generator_branch_mesh_ready[index] {
            branch_mesh.destroy(&plant_generator_branch_meshes[index])
            plant_generator_branch_mesh_ready[index] = false
        }
    }
}

plant_generator_support :: proc(species: plants.Species) -> plants.Support_Surface {
    plant_generator_exclusions = {{-1.0, .2, 1.0, 2.8}, {-3.2, 3.4, -1.2, 5.3}, {1.2, 3.4, 3.2, 5.3}}
    return {
        width = 8,
        height = 7,
        plane_z = .18,
        root_x = species == .Bougainvillea ? f32(-2.7) : f32(0),
        planter = species == .Bougainvillea,
        exclusions = species == .Bougainvillea ? plant_generator_exclusions[:] : nil,
    }
}

plant_generator_rebuild :: proc() {
    plant_generator_destroy()
    for index in 0 ..< plants.SPECIES_COUNT {
        species := plants.Species(index)
        habit := plants.default_habit(species)
        support := plant_generator_support(species)
        support_pointer: ^plants.Support_Surface
        if habit != .Free_Standing do support_pointer = &support
        result := plants.generate(
            {
                species = species,
                seed = plant_generator_seed + u64(index * 977),
                maturity = plant_generator_maturity,
                detail = plant_generator_detail,
                habit = habit,
                support = support_pointer,
            },
        )
        if result.error != .None {
            plants.destroy(&result)
            continue
        }
        plant_generator_results[index] = result
        plant_generator_ready[index] = true
        branch_config := branch_mesh.Config {
            minimum_radius      = .012,
            radial_irregularity = result.plant.wood.radial_irregularity,
            twist               = result.plant.wood.twist,
            seed                = plant_generator_seed + u64(index * 977),
        }
        if species == .Thyme do branch_config.minimum_radius = .0035
        if species == .Myrtle do branch_config.minimum_radius = .007
        if species == .Mastic do branch_config.minimum_radius = .006
        if species == .Oleander do branch_config.minimum_radius = .008
        if species == .Pomegranate do branch_config.minimum_radius = .008
        if species == .Prickly_Pear do branch_config.minimum_radius = .006
        switch plant_generator_detail {
        case .Near:
            branch_config.radial_segments = 8
            branch_config.samples_per_segment = 3
        case .Medium:
            branch_config.radial_segments = 6
            branch_config.samples_per_segment = 2
        case .Far:
            branch_config.radial_segments = 4
            branch_config.samples_per_segment = 1
        }
        if species == .Olive && plant_generator_detail == .Near {
            branch_config.radial_segments = 12
            branch_config.samples_per_segment = 4
        }
        plant_generator_branch_meshes[index] = branch_mesh.generate(result.plant.segments[:], branch_config)
        plant_generator_branch_mesh_ready[index] = len(plant_generator_branch_meshes[index].indices) > 0
        for attachment in result.plant.attachments {
            if attachment.kind != .Leaf do continue
            variant := int(attachment.variant)
            if plant_generator_leaf_mesh_ready[index][variant] do continue
            config := leaf_mesh.defaults(attachment.leaf.shape)
            config.length = attachment.leaf.length
            config.width = attachment.leaf.width
            config.serration = attachment.leaf.serration
            config.curl = attachment.leaf.curl
            config.cup = attachment.leaf.cup
            config.stem = attachment.leaf.length * .08
            switch plant_generator_detail {
            case .Near:
                config.segments = 12
            case .Medium:
                config.segments = 6
            case .Far:
                config.segments = 3
            }
            if attachment.leaf.shape == .Cypress_Spray {
                // The spray outline encodes overlapping scale lobes; the
                // generic three-row far mesh collapses it back into a single
                // broad leaf card.
                config.segments = plant_generator_detail == .Far ? 8 : plant_generator_detail == .Medium ? 12 : 20
            }
            plant_generator_leaf_meshes[index][variant] = leaf_mesh.generate(config)
            plant_generator_leaf_mesh_ready[index][variant] = true
        }
        for attachment in result.plant.attachments {
            if attachment.kind != .Flower do continue
            flower_config := flower_mesh.defaults()
            flower_config.segments = plant_generator_detail == .Near ? 7 : 4
            flower_config.center_segments = plant_generator_detail == .Near ? 10 : 6
            flower_config.petal_length = .12
            flower_config.petal_width = .075
            flower_config.base_radius = .015
            flower_config.center_radius = .028
            flower_config.center_height = .018
            #partial switch species {
            case .Bougainvillea:
                flower_config.petal_count = 3
                flower_config.petal_shape = .Pointed
                flower_config.petal_length = .16
                flower_config.petal_width = .13
            case .Oleander:
                flower_config.petal_count = 5
                flower_config.petal_shape = .Rounded
                flower_config.petal_length = .15
            case .Almond:
                flower_config.petal_count = 5
                flower_config.petal_shape = .Notched
            case .Lemon:
                flower_config.petal_count = 5
                flower_config.petal_shape = .Pointed
                // Lemon blossom is a small white star tucked among glossy
                // leaves, not a fruit-sized yellow accent.
                flower_config.petal_length = .070
                flower_config.petal_width = .040
                flower_config.base_radius = .010
                flower_config.center_radius = .018
            case .Pomegranate:
                flower_config.petal_count = 6
                flower_config.petal_shape = .Rounded
            case .Lavender, .Sage:
                flower_config.petal_count = 5
                flower_config.petal_shape = .Rounded
                flower_config.petal_length = .09
            case .Pelargonium:
                // Several small five-petalled florets combine into the
                // elevated rounded umbel authored by the plant skeleton.
                flower_config.petal_count = 5
                flower_config.petal_shape = .Rounded
                flower_config.petal_length = .055
                flower_config.petal_width = .036
                flower_config.base_radius = .009
                flower_config.center_radius = .014
            case .Thyme, .Myrtle, .Strawberry_Tree, .Bay_Laurel:
                flower_config.petal_count = 5
                flower_config.petal_shape = .Pointed
                flower_config.petal_length = .08
            case .Olive, .Italian_Cypress, .Grapevine, .Fig, .Rosemary, .Stone_Pine, .Carob, .Mastic, .Prickly_Pear:
            }
            flower_stages := [4]flower_mesh.Lifecycle_Stage{.Bud, .Opening, .Half_Open, .Bloom}
            for flower_stage, stage_index in flower_stages {
                plant_generator_flower_meshes[index][stage_index] = flower_mesh.generate_lifecycle(
                    {stage = flower_stage, flower = flower_config, fruit = flower_mesh.fruit_defaults()},
                )
                plant_generator_flower_mesh_ready[index][stage_index] = true
            }
            break
        }
        for attachment in result.plant.attachments {
            if attachment.kind != .Fruit do continue
            fruit_config := flower_mesh.fruit_defaults(.Berry)
            fruit_config.segments = plant_generator_detail == .Near ? 12 : 8
            fruit_config.rings = plant_generator_detail == .Near ? 8 : 5
            #partial switch species {
            case .Italian_Cypress:
                fruit_config = flower_mesh.fruit_defaults(.Pome)
                fruit_config.radius = .050
                fruit_config.length = .055
                fruit_config.ridges = 8
                fruit_config.ridge_depth = .12
                fruit_config.tip = 0
            case .Olive:
                fruit_config = flower_mesh.fruit_defaults(.Drupe)
                fruit_config.radius = .028
                fruit_config.length = .060
            case .Grapevine:
                fruit_config = flower_mesh.fruit_defaults(.Berry)
                fruit_config.radius = .038
                fruit_config.length = .070
            case .Fig:
                fruit_config = flower_mesh.fruit_defaults(.Pome)
                fruit_config.radius = .060
                fruit_config.length = .095
                fruit_config.ridges = 0
            case .Lemon:
                fruit_config = flower_mesh.fruit_defaults(.Citrus)
                fruit_config.radius = .068
                fruit_config.length = .145
            case .Pomegranate:
                fruit_config = flower_mesh.fruit_defaults(.Pome)
                fruit_config.radius = .075
                fruit_config.length = .105
                fruit_config.ridges = 6
            case .Carob:
                fruit_config = flower_mesh.fruit_defaults(.Drupe)
                fruit_config.radius = .035
                fruit_config.length = .18
            case .Strawberry_Tree:
                fruit_config = flower_mesh.fruit_defaults(.Berry)
                fruit_config.radius = .052
                fruit_config.length = .062
            case .Myrtle, .Mastic:
                fruit_config = flower_mesh.fruit_defaults(.Berry)
                fruit_config.radius = .025
                fruit_config.length = .040
            case .Prickly_Pear:
                fruit_config = flower_mesh.fruit_defaults(.Berry)
                fruit_config.radius = .065
                fruit_config.length = .12
            case .Almond, .Oleander, .Bougainvillea, .Rosemary, .Stone_Pine, .Bay_Laurel, .Lavender, .Thyme, .Sage:
            }
            fruit_config.segments = plant_generator_detail == .Near ? 12 : 8
            fruit_config.rings = plant_generator_detail == .Near ? 8 : 5
            fruit_stages := [4]flower_mesh.Lifecycle_Stage{.Fruit_Set, .Immature_Fruit, .Ripening_Fruit, .Ripe_Fruit}
            for fruit_stage, stage_index in fruit_stages {
                plant_generator_fruit_meshes[index][stage_index] = flower_mesh.generate_lifecycle(
                    {stage = fruit_stage, flower = flower_mesh.defaults(), fruit = fruit_config},
                )
                plant_generator_fruit_mesh_ready[index][stage_index] = true
            }
            break
        }
    }
}

plant_generator_configure_camera :: proc(editor: ^Editor) {
    if editor == nil do return
    if plant_generator_isolated >= 0 && plant_generator_ready[plant_generator_isolated] {
        species := plants.Species(plant_generator_isolated)
        generated := &plant_generator_results[plant_generator_isolated].plant
        scale := plant_generator_display_scale(species)
        width :=
            max(
                generated.bounds.maximum[0] - generated.bounds.minimum[0],
                generated.bounds.maximum[2] - generated.bounds.minimum[2],
            ) *
            scale
        height := (generated.bounds.maximum[1] - generated.bounds.minimum[1]) * scale
        // Fit inspection captures directly to generated bounds. The camera
        // pose sits roughly 2.6 radii from its focus, so these padded
        // half-extents keep both the vertical and horizontal silhouette in
        // frame without species-specific distance overrides.
        radius := generated.habit == .Free_Standing ? max(max(width * .58, height * .64), f32(.42)) : f32(4.8)
        local_focus_x := (generated.bounds.minimum[0] + generated.bounds.maximum[0]) * .5 * scale
        local_focus_z := (generated.bounds.minimum[2] + generated.bounds.maximum[2]) * .5 * scale
        yaw := generated.habit == .Free_Standing ? f32(plant_generator_isolated) * .31 : f32(0)
        cosine, sine := math.cos(yaw), math.sin(yaw)
        focus_x := local_focus_x * cosine - local_focus_z * sine
        focus_z := local_focus_x * sine + local_focus_z * cosine
        focus_y := (generated.bounds.minimum[1] + generated.bounds.maximum[1]) * .5 * scale
        if plant_generator_camera_close {
            if species == .Italian_Cypress {
                // Resolve individual cones while retaining enough of the
                // vertically distributed reproductive crown to judge whether
                // hashed placements form bands or foliage voids.
                radius = .72
                focus_y = (generated.bounds.minimum[1] + generated.bounds.maximum[1]) * .58 * scale
            } else {
                radius = 1.8
                focus_y = .72 * scale
            }
        }
        if plant_generator_camera_base && species == .Italian_Cypress {
            radius = .55
            focus_y = generated.bounds.minimum[1] * scale + .32
        }
        editor.camera_pose = third_person.camera_look_at(
            {focus_x + radius * 1.15, focus_y + radius * .34, focus_z + radius * 2.35},
            {focus_x, focus_y, focus_z},
        )
    } else {
        editor.camera_pose = third_person.camera_look_at({0, 13.5, 29}, {0, 2.1, 0})
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

plant_generator_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    plant_generator_seed = 73
    plant_generator_maturity = 1
    plant_generator_detail = .Near
    plant_generator_isolated = plant_generator_find_species(target)
    plant_generator_camera_close = false
    plant_generator_camera_base = false
    if target == "olive-71" {
        plant_generator_seed = 71
        plant_generator_isolated = int(plants.Species.Olive)
    }
    if target == "olive-79" {
        plant_generator_seed = 79
        plant_generator_isolated = int(plants.Species.Olive)
    }
    if target == "olive-young" {
        plant_generator_maturity = .28
        plant_generator_isolated = int(plants.Species.Olive)
    }
    if target == "olive-growing" {
        plant_generator_maturity = .55
        plant_generator_camera_close = true
        plant_generator_isolated = int(plants.Species.Olive)
    }
    if target == "olive-medium" {
        plant_generator_detail = .Medium
        plant_generator_isolated = int(plants.Species.Olive)
    }
    if target == "olive-far" {
        plant_generator_detail = .Far
        plant_generator_isolated = int(plants.Species.Olive)
    }
    if target == "olive-trunk" {
        plant_generator_camera_close = true
        plant_generator_isolated = int(plants.Species.Olive)
    }
    if target == "cypress-cones" {
        plant_generator_camera_close = true
        plant_generator_isolated = int(plants.Species.Italian_Cypress)
    }
    if target == "cypress-base" {
        plant_generator_camera_base = true
        plant_generator_isolated = int(plants.Species.Italian_Cypress)
    }
    cypress_seed_prefix := "cypress-seed-"
    if len(target) > len(cypress_seed_prefix) && target[:len(cypress_seed_prefix)] == cypress_seed_prefix {
        parsed, ok := strconv.parse_int(target[len(cypress_seed_prefix):])
        if !ok || parsed < 0 {
            return false
        }
        plant_generator_seed = u64(parsed)
        plant_generator_isolated = int(plants.Species.Italian_Cypress)
    }
    lemon_seed_prefix := "lemon-seed-"
    if len(target) > len(lemon_seed_prefix) && target[:len(lemon_seed_prefix)] == lemon_seed_prefix {
        parsed, ok := strconv.parse_int(target[len(lemon_seed_prefix):])
        if !ok || parsed < 0 {
            return false
        }
        plant_generator_seed = u64(parsed)
        plant_generator_isolated = int(plants.Species.Lemon)
    }
    capture_weather := atmosphere.Weather_Preset.Clear
    capture_phase := -1
    for species_index in -1 ..< plants.SPECIES_COUNT {
        species_target := species_index < 0 ? "gallery" : plant_generator_species_slug(plants.Species(species_index))
        presets := [3]atmosphere.Weather_Preset{.Clear, .Windy, .Storm}
        preset_names := [3]string{"calm", "windy", "storm"}
        for preset, preset_index in presets {
            for phase_index in 0 ..< 16 {
                if target == fmt.tprintf("%s-%s-phase16-%d", species_target, preset_names[preset_index], phase_index) {
                    plant_generator_isolated = species_index
                    capture_weather = preset
                    capture_phase = phase_index
                }
            }
        }
    }
    if target == "young" do plant_generator_maturity = .28
    if target == "medium" do plant_generator_detail = .Medium
    if target == "far" do plant_generator_detail = .Far
    if target == "cypress-young" {
        plant_generator_isolated = int(plants.Species.Italian_Cypress)
        plant_generator_maturity = .28
    }
    if target == "cypress-growing" {
        plant_generator_isolated = int(plants.Species.Italian_Cypress)
        plant_generator_maturity = .55
    }
    if target == "cypress-medium" {
        plant_generator_isolated = int(plants.Species.Italian_Cypress)
        plant_generator_detail = .Medium
    }
    if target == "cypress-far" {
        plant_generator_isolated = int(plants.Species.Italian_Cypress)
        plant_generator_detail = .Far
    }
    if target == "lemon-young" {
        plant_generator_isolated = int(plants.Species.Lemon)
        plant_generator_maturity = .28
    }
    if target == "lemon-fruit" {
        plant_generator_isolated = int(plants.Species.Lemon)
        plant_generator_camera_close = true
    }
    if target == "lemon-medium" {
        plant_generator_isolated = int(plants.Species.Lemon)
        plant_generator_detail = .Medium
    }
    if target == "lemon-far" {
        plant_generator_isolated = int(plants.Species.Lemon)
        plant_generator_detail = .Far
    }
    for species_index in 0 ..< plants.SPECIES_COUNT {
        species := plants.Species(species_index)
        for stage_index in 0 ..< 16 {
            if target == fmt.tprintf("%s-lifecycle-%d", plant_generator_species_slug(species), stage_index) {
                plant_generator_isolated = species_index
                plant_generator_maturity = .04 + .96 * f32(stage_index) / 15
            }
        }
    }
    pelargonium_lifecycle100_prefix := "pelargonium-lifecycle100-"
    if len(target) > len(pelargonium_lifecycle100_prefix) &&
       target[:len(pelargonium_lifecycle100_prefix)] == pelargonium_lifecycle100_prefix {
        parsed, ok := strconv.parse_int(target[len(pelargonium_lifecycle100_prefix):])
        if !ok || parsed < 0 || parsed >= 100 do return false
        plant_generator_isolated = int(plants.Species.Pelargonium)
        plant_generator_maturity = .01 + .99 * f32(parsed) / 99
    }
    if target == "constrained" do plant_generator_isolated = int(plants.Species.Bougainvillea)
    plant_generator_rebuild()

    editor.in_map = true
    editor.capture_world_only = plant_generator_camera_close || plant_generator_camera_base
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 15)
    atmosphere.set_weather_override(&editor.atmosphere, capture_weather)
    editor.atmosphere.weather = atmosphere.weather_for(capture_weather)
    if capture_phase >= 0 {
        // Capture targets sample shader time directly, just as gait captures
        // sample stride phase. Fixed increments make every wind review
        // reproducible regardless of launch or frame-settling time.
        editor.atmosphere.front_seconds = f32(capture_phase) * .45
    }
    editor.atmosphere.paused = true
    plant_generator_configure_camera(editor)
    return true
}

plant_generator_lab_process_input :: proc(editor: ^Editor) {
    changed := false
    if rl.IsKeyPressed(.R) {
        plant_generator_seed += 1
        changed = true
    }
    // canvas2d currently exposes arrows but not bracket key codes; arrows are
    // the interactive aliases for the documented [ and ] maturity controls.
    if rl.IsKeyPressed(.LEFT) {
        plant_generator_maturity = max(0, plant_generator_maturity - .1)
        changed = true
    }
    if rl.IsKeyPressed(.RIGHT) {
        plant_generator_maturity = min(1, plant_generator_maturity + .1)
        changed = true
    }
    if rl.IsKeyPressed(.ONE) {
        plant_generator_detail = .Near
        changed = true
    }
    if rl.IsKeyPressed(.TWO) {
        plant_generator_detail = .Medium
        changed = true
    }
    if rl.IsKeyPressed(.THREE) {
        plant_generator_detail = .Far
        changed = true
    }
    if rl.IsKeyPressed(.FOUR) {
        plant_generator_isolated = -1
        changed = true
    }
    if rl.IsKeyPressed(.UP) {
        plant_generator_isolated =
            plant_generator_isolated < 0 ? 0 : (plant_generator_isolated + 1) % plants.SPECIES_COUNT
        changed = true
    }
    if rl.IsKeyPressed(.DOWN) {
        if plant_generator_isolated < 0 {
            plant_generator_isolated = plants.SPECIES_COUNT - 1
        } else {
            plant_generator_isolated = (plant_generator_isolated + plants.SPECIES_COUNT - 1) % plants.SPECIES_COUNT
        }
        changed = true
    }
    if changed {
        plant_generator_rebuild()
        plant_generator_configure_camera(editor)
    }
}

plant_generator_lab_exit :: proc(_: ^Editor) {
    plant_generator_destroy()
}

plant_generator_display_scale :: proc(species: plants.Species) -> f32 {
    #partial switch species {
    case .Italian_Cypress:
        return .60
    case .Rosemary:
        return 3.2
    case .Lavender, .Sage, .Pelargonium:
        return 3.0
    case .Thyme:
        return 4.2
    case .Myrtle, .Mastic, .Prickly_Pear:
        return 2.2
    case .Stone_Pine:
        return 1.35
    case .Bay_Laurel, .Carob, .Strawberry_Tree:
        return 1.55
    case .Bougainvillea, .Grapevine:
        return 1.15
    case .Lemon:
        return 1.25
    case .Olive, .Fig, .Pomegranate, .Almond, .Oleander:
        return 1.65
    }
    return 1
}

plant_generator_point :: proc(base: third_person.Vec3, point: lsystem.Vec3, yaw, scale: f32) -> third_person.Vec3 {
    cosine, sine := math.cos(yaw), math.sin(yaw)
    result := third_person.Vec3 {
        base.x + (point[0] * cosine - point[2] * sine) * scale,
        base.y + point[1] * scale,
        base.z + (point[0] * sine + point[2] * cosine) * scale,
    }
    editor := world_renderer.editor
    if editor == nil || plant_generator_wind_height <= .001 do return result
    wind := editor.atmosphere.weather.wind
    wind_speed := f32(math.sqrt(f64(wind[0] * wind[0] + wind[1] * wind[1])))
    if wind_speed <= .001 do return result
    direction := third_person.Vec3{wind[0] / wind_speed, 0, wind[1] / wind_speed}
    across := third_person.Vec3{-direction.z, 0, direction.x}
    height_weight := clamp((result.y - plant_generator_wind_base.y) / plant_generator_wind_height, 0, 1)
    root_offset := third_person.Vec3{result.x - plant_generator_wind_base.x, 0, result.z - plant_generator_wind_base.z}
    reach_weight := clamp(linalg.length(root_offset) / plant_generator_wind_height, 0, 1)
    // Height alone makes a near-horizontal branch move as one rigid piece:
    // its joint and tip have almost identical weights, even though the leaves
    // at the tip make the motion conspicuous. Radial reach supplies the
    // missing along-branch gradient while the squared response keeps roots
    // and the lower trunk firmly planted.
    flex_weight := clamp(height_weight + reach_weight * .52, 0, 1)
    bend_weight := flex_weight * flex_weight
    time := editor.atmosphere.front_seconds
    phase := time * (.72 + wind_speed * .018) + plant_generator_wind_base.x * .071 - plant_generator_wind_base.z * .053
    gust := f32(math.sin(f64(phase))) * .72 + f32(math.sin(f64(phase * .43 + 1.9))) * .28
    cross_gust := f32(math.sin(f64(phase * 1.31 + 4.2)))
    // Compliance is catalog-authored around .18 for mature free-standing
    // trees. Normalize around that baseline so it controls relative species
    // flexibility while windy weather still produces a readable crown arc.
    compliance := clamp(plant_generator_wind_compliance / .18, .25, 2.4)
    amplitude := clamp((wind_speed - 1) / 13, 0, 1) * .62 * compliance
    result += direction * (amplitude * (.48 + gust * .52) * bend_weight)
    result += across * (amplitude * cross_gust * .13 * bend_weight)
    result.y -= amplitude * .08 * bend_weight * (1 + gust * .3)
    return result
}

plant_generator_colors :: proc(species: plants.Species) -> (wood, leaf, accent: rl.Color) {
    #partial switch species {
    case .Olive:
        return {122, 110, 88, 255}, {105, 123, 83, 255}, {62, 72, 40, 255}
    case .Italian_Cypress:
        return {92, 66, 43, 255}, {38, 78, 52, 255}, {105, 79, 48, 255}
    case .Grapevine:
        return {101, 70, 48, 255}, {82, 118, 62, 255}, {91, 48, 112, 255}
    case .Fig:
        return {112, 80, 50, 255}, {70, 113, 64, 255}, {99, 57, 94, 255}
    case .Lemon:
        return {104, 74, 43, 255}, {67, 116, 55, 255}, {239, 194, 43, 255}
    case .Pomegranate:
        return {108, 73, 45, 255}, {69, 119, 58, 255}, {183, 55, 43, 255}
    case .Almond:
        return {111, 79, 52, 255}, {93, 125, 66, 255}, {235, 184, 188, 255}
    case .Oleander:
        return {86, 74, 49, 255}, {61, 110, 62, 255}, {223, 113, 153, 255}
    case .Bougainvillea:
        return {116, 80, 53, 255}, {58, 107, 58, 255}, {213, 65, 132, 255}
    case .Rosemary:
        return {82, 68, 49, 255}, {72, 118, 89, 255}, {132, 121, 188, 255}
    case .Stone_Pine:
        return {110, 75, 48, 255}, {47, 92, 59, 255}, {116, 87, 52, 255}
    case .Bay_Laurel:
        return {91, 70, 48, 255}, {56, 105, 58, 255}, {226, 211, 139, 255}
    case .Carob:
        return {98, 70, 45, 255}, {58, 101, 54, 255}, {88, 54, 35, 255}
    case .Strawberry_Tree:
        return {146, 78, 54, 255}, {62, 111, 59, 255}, {207, 66, 48, 255}
    case .Myrtle:
        return {90, 70, 50, 255}, {48, 105, 67, 255}, {62, 63, 91, 255}
    case .Mastic:
        return {87, 68, 47, 255}, {55, 106, 62, 255}, {119, 53, 77, 255}
    case .Lavender:
        return {83, 71, 53, 255}, {104, 128, 105, 255}, {137, 99, 180, 255}
    case .Thyme:
        return {86, 72, 52, 255}, {110, 143, 96, 255}, {190, 125, 174, 255}
    case .Sage:
        return {91, 75, 54, 255}, {137, 151, 123, 255}, {142, 102, 176, 255}
    case .Prickly_Pear:
        return {91, 93, 54, 255}, {83, 139, 73, 255}, {212, 89, 56, 255}
    case .Pelargonium:
        return {96, 105, 66, 255}, {67, 119, 69, 255}, {224, 72, 111, 255}
    }
    return {100, 75, 50, 255}, {65, 110, 60, 255}, {220, 160, 90, 255}
}

plant_generator_leaf_color :: proc(species: plants.Species, variant: u8, fallback: rl.Color) -> rl.Color {
    if species == .Pelargonium {
        switch variant % 4 {
        case 0:
            return {73, 128, 72, 255}
        case 1:
            return {55, 105, 59, 255}
        case 2:
            return {91, 139, 79, 255}
        case 3:
            return {63, 114, 64, 255}
        }
    }
    if species != .Olive do return fallback
    switch variant % 4 {
    case 0:
        return {125, 137, 105, 255}
    case 1:
        return {91, 110, 74, 255}
    case 2:
        return {145, 150, 120, 255}
    case 3:
        return {101, 120, 82, 255}
    }
    return fallback
}

plant_generator_leaf_point :: proc(
    base: third_person.Vec3,
    position, right, forward, up: lsystem.Vec3,
    point: [3]f32,
    yaw, scale: f32,
) -> third_person.Vec3 {
    local := position + (right * point[0] + forward * point[1] + up * point[2]) / scale
    return plant_generator_point(base, local, yaw, scale)
}

plant_generator_draw_leaf :: proc(
    base: third_person.Vec3,
    species: plants.Species,
    attachment: plants.Attachment,
    yaw, display_scale: f32,
    color: rl.Color,
) {
    variant := int(attachment.variant)
    if !plant_generator_leaf_mesh_ready[int(species)][variant] do return
    mesh := &plant_generator_leaf_meshes[int(species)][variant]
    presentation_scale := f32(3.1)
    if species == .Italian_Cypress do presentation_scale = 2.2
    if species == .Rosemary do presentation_scale = 5.0
    if species == .Thyme do presentation_scale = 8.0
    if species == .Myrtle do presentation_scale = 4.6
    if species == .Mastic do presentation_scale = 4.4
    if species == .Pomegranate do presentation_scale = 3.9
    if species == .Prickly_Pear do presentation_scale = 2.4

    forward := linalg.normalize0(attachment.forward)
    up := linalg.normalize0(attachment.up)
    if species == .Prickly_Pear {
        // Generic leaves extend along the shoot direction. Opuntia cladodes
        // instead stand vertically, with their broad faces rotating around
        // the branching joint.
        pad_normal := lsystem.Vec3{attachment.forward[0], 0, attachment.forward[2]}
        if linalg.dot(pad_normal, pad_normal) < .001 {
            pad_normal = {attachment.up[0], 0, attachment.up[2]}
        }
        if linalg.dot(pad_normal, pad_normal) < .001 do pad_normal = {0, 0, 1}
        pad_angle := f64(attachment.variant) * .71 + f64(attachment.depth) * .37
        pad_cosine, pad_sine := f32(math.cos(pad_angle)), f32(math.sin(pad_angle))
        pad_normal = {
            pad_normal[0] * pad_cosine - pad_normal[2] * pad_sine,
            0,
            pad_normal[0] * pad_sine + pad_normal[2] * pad_cosine,
        }
        forward = {0, 1, 0}
        up = linalg.normalize0(pad_normal)
    }
    right := linalg.normalize0(linalg.cross(forward, up))
    if linalg.dot(right, right) < .001 do right = {1, 0, 0}
    up = linalg.normalize0(linalg.cross(right, forward))
    for first := 0; first + 2 < mesh.index_count; first += 3 {
        a := plant_generator_leaf_point(
            base,
            attachment.position,
            right,
            forward,
            up,
            mesh.vertices[mesh.indices[first + 0]].position * presentation_scale,
            yaw,
            display_scale,
        )
        b := plant_generator_leaf_point(
            base,
            attachment.position,
            right,
            forward,
            up,
            mesh.vertices[mesh.indices[first + 1]].position * presentation_scale,
            yaw,
            display_scale,
        )
        c := plant_generator_leaf_point(
            base,
            attachment.position,
            right,
            forward,
            up,
            mesh.vertices[mesh.indices[first + 2]].position * presentation_scale,
            yaw,
            display_scale,
        )
        normal := linalg.normalize0(linalg.cross(b - a, c - a))
        world_triangle_smooth_lit(a, b, c, normal, normal, normal, color, color, color, .86)
        world_triangle_smooth_lit(c, b, a, -normal, -normal, -normal, color, color, color, .86)
    }
}

plant_generator_draw_flower :: proc(
    position: third_person.Vec3,
    species: plants.Species,
    attachment: plants.Attachment,
    display_scale: f32,
    color: rl.Color,
) {
    stage_index := 3
    #partial switch attachment.stage {
    case .Bud:
        stage_index = 0
    case .Opening:
        stage_index = 1
    case .Half_Open:
        stage_index = 2
    case .Bloom, .None:
        stage_index = 3
    case .Fruit_Set, .Immature_Fruit, .Ripening_Fruit, .Ripe_Fruit:
    }
    if !plant_generator_flower_mesh_ready[int(species)][stage_index] do return
    mesh := &plant_generator_flower_meshes[int(species)][stage_index]
    outward := linalg.normalize0(attachment.forward)
    up := linalg.normalize0(attachment.up)
    right := linalg.normalize0(linalg.cross(up, outward))
    if linalg.dot(right, right) < .001 do right = {1, 0, 0}
    up = linalg.normalize0(linalg.cross(outward, right))
    // Flower measurements describe individual petals; boost ornamental
    // blossoms for presentation, but keep fruit-tree corollas at botanical
    // scale relative to their fruit.
    scale := clamp(display_scale, f32(.72), f32(1.4)) * 1.8
    floret_count := 1
    if species == .Lemon {
        // A lemon blossom is only a few centimetres across. The generic
        // presentation boost made each one wider than the mature lemon.
        scale = .18
    } else if species == .Pomegranate {
        // Keep the compact scarlet corolla clearly smaller than the fruit it
        // precedes instead of letting it fill the surrounding leaf cluster.
        scale = .22
    } else if species == .Strawberry_Tree {
        // Strawberry-tree flowers are small hanging bells, roughly a
        // centimetre across, borne in clusters.
        scale = .09
    } else if species == .Lavender {
        // Lavender carries many tiny corollas along a narrow terminal spike.
        // One enlarged generic flower turns adjacent attachments into solid
        // purple pom-poms, so render a short run of small staggered florets.
        scale = .52
        floret_count = 4
    } else if species == .Thyme {
        // Thyme flowers are tiny lip-like whorls tucked into the mat, not
        // full-size garden corollas. A compact three-floret cluster keeps the
        // bloom readable without obscuring the creeping foliage beneath it.
        scale = .30
        floret_count = 3
    } else if species == .Sage {
        // Sage flowers climb in spaced whorls above the silver leaf mound.
        // A narrow vertical run reads as a flower spike; one large generic
        // corolla reads as purple disks pasted throughout the shrub.
        scale = .38
        floret_count = 5
    } else if species == .Oleander {
        // Oleander blooms collect into loose terminal cymes. Several modest
        // corollas read as a cluster without masking the narrow leaves.
        scale = .95
        floret_count = 3
    }
    for floret_index in 0 ..< floret_count {
        floret_position := position
        if species == .Lavender {
            floret_position.y += (.5 - f32(floret_index)) * .052
            floret_position += right * (floret_index % 2 == 0 ? f32(-.018) : f32(.018))
        } else if species == .Thyme {
            floret_position.y += (.5 - f32(floret_index)) * .026
            floret_position += right * (floret_index % 2 == 0 ? f32(-.012) : f32(.012))
        } else if species == .Sage {
            floret_position.y += (1.5 - f32(floret_index)) * .045
            floret_position += right * (floret_index % 2 == 0 ? f32(-.014) : f32(.014))
        } else if species == .Oleander {
            floret_position.y += (floret_index == 0 ? f32(.035) : f32(-.018))
            if floret_index > 0 {
                floret_position += right * (floret_index == 1 ? f32(-.055) : f32(.055))
            }
        }
        for first := 0; first + 2 < mesh.index_count; first += 3 {
            points: [3]third_person.Vec3
            normals: [3]third_person.Vec3
            for point_index in 0 ..< 3 {
                vertex := mesh.vertices[mesh.indices[first + point_index]]
                points[point_index] =
                    floret_position +
                    right * vertex.position[0] * scale +
                    up * vertex.position[1] * scale +
                    outward * vertex.position[2] * scale
                normals[point_index] = linalg.normalize0(
                    right * vertex.normal[0] + up * vertex.normal[1] + outward * vertex.normal[2],
                )
            }
            world_triangle_smooth_lit(
                points[0],
                points[1],
                points[2],
                normals[0],
                normals[1],
                normals[2],
                color,
                color,
                color,
                .88,
            )
        }
    }
}

plant_generator_draw_fruit :: proc(
    position: third_person.Vec3,
    species: plants.Species,
    attachment: plants.Attachment,
    display_scale: f32,
    color: rl.Color,
) {
    stage_index := 3
    #partial switch attachment.stage {
    case .Fruit_Set:
        stage_index = 0
    case .Immature_Fruit:
        stage_index = 1
    case .Ripening_Fruit:
        stage_index = 2
    case .Ripe_Fruit, .None:
        stage_index = 3
    case .Bud, .Opening, .Half_Open, .Bloom:
    }
    if !plant_generator_fruit_mesh_ready[int(species)][stage_index] do return
    mesh := &plant_generator_fruit_meshes[int(species)][stage_index]
    outward := linalg.normalize0(attachment.forward)
    if species == .Lemon {
        // Citrus stems yield under fruit weight. Retain a little attachment
        // direction so neighboring lemons do not become perfectly parallel,
        // but bias the long axis strongly downward.
        outward = linalg.normalize0(outward * .22 + third_person.Vec3{0, -1, 0})
    }
    up := linalg.normalize0(attachment.up)
    right := linalg.normalize0(linalg.cross(up, outward))
    if linalg.dot(right, right) < .001 do right = {1, 0, 0}
    up = linalg.normalize0(linalg.cross(outward, right))
    scale := clamp(display_scale, f32(.72), f32(1.35)) * (1 + f32(attachment.variant) * .035)
    for first := 0; first + 2 < mesh.index_count; first += 3 {
        points: [3]third_person.Vec3
        normals: [3]third_person.Vec3
        for point_index in 0 ..< 3 {
            vertex := mesh.vertices[mesh.indices[first + point_index]]
            points[point_index] =
                position +
                right * vertex.position[0] * scale +
                up * vertex.position[1] * scale +
                outward * vertex.position[2] * scale
            normals[point_index] = linalg.normalize0(
                right * vertex.normal[0] + up * vertex.normal[1] + outward * vertex.normal[2],
            )
        }
        world_triangle_smooth_lit(
            points[0],
            points[1],
            points[2],
            normals[0],
            normals[1],
            normals[2],
            color,
            color,
            color,
            .84,
        )
    }
}

plant_generator_draw_branch_hull :: proc(
    index: int,
    base: third_person.Vec3,
    yaw, display_scale: f32,
    color: rl.Color,
) {
    if !plant_generator_branch_mesh_ready[index] do return
    mesh := &plant_generator_branch_meshes[index]
    cosine, sine := math.cos(yaw), math.sin(yaw)
    for first := 0; first + 2 < len(mesh.indices); first += 3 {
        points: [3]third_person.Vec3
        normals: [3]third_person.Vec3
        colors := [3]rl.Color{color, color, color}
        for point_index in 0 ..< 3 {
            vertex := mesh.vertices[mesh.indices[first + point_index]]
            points[point_index] = plant_generator_point(base, vertex.position, yaw, display_scale)
            normals[point_index] = linalg.normalize0(
                third_person.Vec3 {
                    vertex.normal[0] * cosine - vertex.normal[2] * sine,
                    vertex.normal[1],
                    vertex.normal[0] * sine + vertex.normal[2] * cosine,
                },
            )
            if plants.Species(index) == .Olive {
                angle := math.atan2(vertex.normal[2], vertex.normal[0])
                grain :=
                    math.sin(angle * 5 + vertex.position[1] * 1.5) * .07 +
                    math.sin(angle * 9 - vertex.position[1] * .7) * .035
                colors[point_index] = {
                    r = u8(clamp(f32(color.r) * (1 + grain), 0, 255)),
                    g = u8(clamp(f32(color.g) * (1 + grain), 0, 255)),
                    b = u8(clamp(f32(color.b) * (1 + grain), 0, 255)),
                    a = color.a,
                }
            }
        }
        world_triangle_smooth_lit(
            points[0],
            points[1],
            points[2],
            normals[0],
            normals[1],
            normals[2],
            colors[0],
            colors[1],
            colors[2],
            .78,
        )
    }
}

plant_generator_stage_color :: proc(color: rl.Color, stage: plants.Attachment_Stage) -> rl.Color {
    green := rl.Color{91, 132, 67, color.a}
    green_weight: f32
    #partial switch stage {
    case .Bud:
        green_weight = .34
    case .Opening:
        green_weight = .18
    case .Half_Open:
        green_weight = .07
    case .Bloom, .Ripe_Fruit, .None:
        green_weight = 0
    case .Fruit_Set:
        green_weight = .82
    case .Immature_Fruit:
        green_weight = .62
    case .Ripening_Fruit:
        green_weight = .28
    }
    return {
        r = u8(clamp(f32(color.r) * (1 - green_weight) + f32(green.r) * green_weight, 0, 255)),
        g = u8(clamp(f32(color.g) * (1 - green_weight) + f32(green.g) * green_weight, 0, 255)),
        b = u8(clamp(f32(color.b) * (1 - green_weight) + f32(green.b) * green_weight, 0, 255)),
        a = color.a,
    }
}

plant_generator_draw_result :: proc(index: int, base: third_person.Vec3) {
    if index < 0 || index >= plants.SPECIES_COUNT || !plant_generator_ready[index] do return
    result := &plant_generator_results[index].plant
    species := plants.Species(index)
    wood, leaf_color, accent := plant_generator_colors(species)
    yaw := result.habit == .Free_Standing ? f32(index) * .31 : f32(0)
    display_scale := plant_generator_display_scale(species)
    plant_generator_wind_base = base
    plant_generator_wind_height = max((result.bounds.maximum[1] - result.bounds.minimum[1]) * display_scale, f32(.1))
    plant_generator_wind_compliance = result.wind_compliance
    if result.habit != .Free_Standing {
        // A wall panel and trellis make the climbers' constraints legible.
        world_box({base.x, 3.5, base.z - .16}, {8.8, 7.2, .24}, {197, 187, 161, 255})
        if result.habit == .Trellised {
            for rail in 1 ..= 4 {
                y := f32(rail) * 1.25
                world_tube_between(
                    {base.x - 3.8, y, base.z},
                    {base.x + 3.8, y, base.z},
                    {0, 1, 0},
                    .035,
                    .035,
                    {91, 72, 55, 255},
                )
            }
        }
    }
    plant_generator_draw_branch_hull(index, base, yaw, display_scale, wood)
    for attachment in result.attachments {
        position := plant_generator_point(base, attachment.position, yaw, display_scale)
        color := attachment.kind == .Leaf || attachment.kind == .Tendril ? leaf_color : accent
        if species == .Lemon && attachment.kind == .Flower {
            color = {244, 239, 218, 255}
        }
        if species == .Italian_Cypress && attachment.kind == .Fruit {
            // Young cones stay olive green; older variants dry toward warm
            // woody brown. Both remain distinct against the blue-green crown.
            color = attachment.variant < 2 ? rl.Color{119, 128, 68, 255} : rl.Color{164, 117, 66, 255}
        }
        if attachment.kind == .Flower || attachment.kind == .Fruit {
            color = plant_generator_stage_color(color, attachment.stage)
        }
        if attachment.kind == .Leaf {
            color = plant_generator_leaf_color(species, attachment.variant, color)
            plant_generator_draw_leaf(base, species, attachment, yaw, display_scale, color)
            continue
        }
        if attachment.kind == .Flower {
            plant_generator_draw_flower(position, species, attachment, display_scale, color)
            continue
        }
        if attachment.kind == .Fruit {
            plant_generator_draw_fruit(position, species, attachment, display_scale, color)
            continue
        }
        if attachment.kind == .Thorn || attachment.kind == .Tendril {
            direction := linalg.normalize0(attachment.forward)
            reach := attachment.kind == .Thorn ? f32(.12) : f32(.22)
            bend := position + direction * reach * .58 + linalg.normalize0(attachment.up) * reach * .20
            tip := position + direction * reach
            radius := attachment.kind == .Thorn ? f32(.012) : f32(.008)
            world_tube_between(position, bend, {0, 1, 0}, radius, radius * .62, color)
            world_tube_between(bend, tip, {0, 1, 0}, radius * .62, .0015, color)
            continue
        }
    }
}

world_plant_generator_lab :: proc(_: ^Editor) {
    world_box({0, -.18, 0}, {40, .34, 24}, {116, 133, 83, 255})
    if plant_generator_isolated >= 0 {
        plant_generator_draw_result(plant_generator_isolated, {0, 0, 0})
        return
    }
    // Eight free-standing plots occupy the first four columns; the final
    // column contains the wall-trained and trellised climbers.
    free_order := [8]plants.Species {
        .Olive,
        .Italian_Cypress,
        .Fig,
        .Lemon,
        .Pomegranate,
        .Almond,
        .Oleander,
        .Rosemary,
    }
    for species, order_index in free_order {
        column := order_index % 4
        row := order_index / 4
        base := third_person.Vec3{-13.5 + f32(column) * 7.1, 0, -4.7 + f32(row) * 9.4}
        world_box({base.x, .03, base.z}, {5.8, .06, 5.8}, {99, 78, 49, 255})
        plant_generator_draw_result(int(species), base)
    }
    plant_generator_draw_result(int(plants.Species.Bougainvillea), {13.8, 0, -4.7})
    plant_generator_draw_result(int(plants.Species.Grapevine), {13.8, 0, 4.7})
}

plant_generator_lab_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    panel := rl.Rectangle{24, 24, 560, 126}
    rl.DrawRectangleRounded(panel, .14, 8, {19, 31, 27, 232})
    rl.DrawRectangleRoundedLinesEx(panel, .14, 8, 1, {111, 146, 111, 255})
    rl.DrawTextEx(rl.Font{}, "ADRIATIC PLANT GENERATOR", {38, 38}, 18, 1, {232, 224, 189, 255})
    detail_name := plant_generator_detail == .Near ? "NEAR" : plant_generator_detail == .Medium ? "MEDIUM" : "FAR"
    summary := fmt.ctprintf(
        "SEED %d  /  MATURITY %.0f%%  /  %s",
        plant_generator_seed,
        plant_generator_maturity * 100,
        detail_name,
    )
    rl.DrawTextEx(rl.Font{}, summary, {38, 66}, 13, 1, {174, 207, 160, 255})
    rl.DrawTextEx(
        rl.Font{},
        "R SEED   LEFT/RIGHT MATURITY   UP/DOWN SPECIES   1/2/3 DETAIL   4 GALLERY",
        {38, 91},
        11,
        1,
        {184, 191, 174, 255},
    )
    if plant_generator_isolated >= 0 {
        isolated_label := fmt.ctprintf("%s", plants.species_name(plants.Species(plant_generator_isolated)))
        rl.DrawTextEx(rl.Font{}, isolated_label, {38, 116}, 10, 1, {216, 194, 151, 255})
    } else {
        rl.DrawTextEx(
            rl.Font{},
            "OLIVE  CYPRESS  FIG  LEMON  /  POMEGRANATE  ALMOND  OLEANDER  ROSEMARY  /  BOUGAINVILLEA  GRAPEVINE",
            {38, 116},
            10,
            1,
            {216, 194, 151, 255},
        )
    }
}
