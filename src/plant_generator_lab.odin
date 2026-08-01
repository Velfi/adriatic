package main

import atmosphere "../packages/atmosphere"
import barrel_cactus_mesh "../packages/barrel_cactus_mesh"
import branch_mesh "../packages/branch_mesh"
import flower_mesh "../packages/flower_mesh"
import leaf_mesh "../packages/leaf_mesh"
import lsystem "../packages/lsystem"
import plant_bark "../packages/plant_bark"
import plants "../packages/plants"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strconv"
import "core:testing"
import canvas2d "zelda_engine:canvas2d"

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
plant_generator_barrel_mesh: barrel_cactus_mesh.Mesh
plant_generator_barrel_mesh_ready: bool
plant_generator_wind_base: third_person.Vec3
plant_generator_wind_height: f32
plant_generator_wind_compliance: f32
plant_generator_camera_close := false
plant_generator_camera_base := false
plant_generator_succulent_garden := false
plant_generator_climbing_garden := false

PLANT_GENERATOR_CAPTURE_ASPECT :: f32(ADRIATIC_WORLD_WIDTH) / f32(ADRIATIC_WORLD_HEIGHT)
// Camera-space depth inside broad rosettes makes their nearest leaf tips
// project beyond a flat extent fit. Keep enough perspective safety margin
// for those tips without returning tall species to the former distant view.
PLANT_GENERATOR_FRAME_MARGIN :: f32(.46)

plant_generator_frame_radius :: proc(width, height: f32) -> f32 {
    // Projection uses viewport height for both axes, so horizontal room is
    // wider by the capture aspect. Normalize width into vertical-screen
    // units before choosing the limiting silhouette dimension.
    screen_extent := max(height, width / PLANT_GENERATOR_CAPTURE_ASPECT)
    return max(screen_extent * PLANT_GENERATOR_FRAME_MARGIN, f32(.42))
}

@(test)
plant_generator_frame_radius_respects_capture_aspect :: proc(t: ^testing.T) {
    tall := plant_generator_frame_radius(1, 6)
    equally_limiting_wide := plant_generator_frame_radius(6 * PLANT_GENERATOR_CAPTURE_ASPECT, 1)
    testing.expect(t, math.abs(tall - equally_limiting_wide) < .0001)
    testing.expect(t, plant_generator_frame_radius(12, 1) > plant_generator_frame_radius(4, 1))
}

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
    case .Wisteria:
        return "wisteria"
    case .Climbing_Rose:
        return "climbing-rose"
    case .Hydrangea_Bush:
        return "hydrangea-bush"
    case .Hydrangea_Tree:
        return "hydrangea-tree"
    case .Agapanthus:
        return "agapanthus"
    case .Star_Jasmine:
        return "star-jasmine"
    case .Holm_Oak:
        return "holm-oak"
    case .Oriental_Plane:
        return "oriental-plane"
    case .European_Hackberry:
        return "european-hackberry"
    case .White_Poplar:
        return "white-poplar"
    case .Golden_Barrel:
        return "golden-barrel"
    case .Agave:
        return "agave"
    case .Aloe:
        return "aloe"
    case .Aeonium:
        return "aeonium"
    case .Echeveria:
        return "echeveria"
    case .Jade_Plant:
        return "jade"
    case .Stonecrop:
        return "stonecrop"
    case .Blue_Chalk_Sticks:
        return "blue-chalk-sticks"
    case .Golden_Torch_Cactus:
        return "golden-torch"
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
    if plant_generator_barrel_mesh_ready {
        barrel_cactus_mesh.destroy(&plant_generator_barrel_mesh)
        plant_generator_barrel_mesh_ready = false
    }
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
    neutral_bougainvillea := species == .Bougainvillea && plant_generator_climbing_garden
    return {
        width = 8,
        height = 7,
        plane_z = .18,
        root_x = species == .Bougainvillea && !neutral_bougainvillea ? f32(-2.7) : f32(0),
        planter = species == .Bougainvillea,
        exclusions = species == .Bougainvillea && !neutral_bougainvillea ? plant_generator_exclusions[:] : nil,
    }
}

plant_generator_rebuild :: proc() {
    plant_generator_destroy()
    for index in 0 ..< plants.SPECIES_COUNT {
        // Named captures and the interactive isolate mode only draw one
        // species. Avoid generating and meshing the entire catalog first;
        // climber density correctly scales with its support area, so doing
        // that hidden work is especially wasteful for wall-sized specimens.
        if plant_generator_isolated >= 0 && index != plant_generator_isolated do continue
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
        if species == .Golden_Barrel {
            barrel_config := barrel_cactus_mesh.defaults()
            barrel_config.radius = .13 + plant_generator_maturity * .17
            barrel_config.height = .20 + plant_generator_maturity * .32
            switch plant_generator_detail {
            case .Near:
                barrel_config.ribs = 20
                barrel_config.vertical_rings = 12
            case .Medium:
                barrel_config.ribs = 14
                barrel_config.vertical_rings = 8
            case .Far:
                barrel_config.ribs = 9
                barrel_config.vertical_rings = 5
            }
            plant_generator_barrel_mesh = barrel_cactus_mesh.generate(barrel_config)
            plant_generator_barrel_mesh_ready = len(plant_generator_barrel_mesh.indices) > 0
        }
        branch_config := branch_mesh.Config {
            minimum_radius      = .012,
            radial_irregularity = result.plant.wood.radial_irregularity,
            twist               = result.plant.wood.twist,
            seed                = plant_generator_seed + u64(index * 977),
        }
        if species == .Thyme do branch_config.minimum_radius = .0007
        if species == .Myrtle do branch_config.minimum_radius = .007
        if species == .Mastic do branch_config.minimum_radius = .006
        if species == .Oleander do branch_config.minimum_radius = .008
        if species == .Pomegranate do branch_config.minimum_radius = .008
        if species == .Prickly_Pear do branch_config.minimum_radius = .006
        if species == .Agapanthus do branch_config.minimum_radius = .003
        if species == .Lavender do branch_config.minimum_radius = .0006
        if species == .Sage do branch_config.minimum_radius = .0035
        if species == .Pelargonium do branch_config.minimum_radius = .0005
        if species == .Rosemary do branch_config.minimum_radius = .0005
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
            config.thickness = attachment.leaf.thickness
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
            case .Hydrangea_Bush, .Hydrangea_Tree:
                // The rendered unit is one small sterile floret; the draw
                // path gathers several into the species-defining mophead.
                flower_config.petal_count = 4
                flower_config.petal_shape = .Rounded
                flower_config.petal_length = .070
                flower_config.petal_width = .052
                flower_config.base_radius = .008
                flower_config.center_radius = .012
            case .Agapanthus:
                flower_config.petal_count = 6
                flower_config.petal_shape = .Pointed
                flower_config.petal_length = .055
                flower_config.petal_width = .032
                flower_config.base_radius = .007
                flower_config.center_radius = .010
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
                // Mature pomegranates are a primary species cue at the lab's
                // full-plant framing. The previous fruit was smaller than a
                // leaf cluster in projection and read as isolated red pixels.
                fruit_config.radius = .095
                fruit_config.length = .135
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

plant_generator_leaf_presentation_scale :: proc(species: plants.Species) -> f32 {
    #partial switch species {
    case .Italian_Cypress:
        return 2.2
    case .Rosemary:
        // Needle leaves are already emitted at very high density. Enlarging
        // them for inspection changes their read from linear needles into
        // broad elliptic paddles and hides the fine woody spray beneath.
        return 1.25
    case .Fig:
        // Fig traits already use full-size palmate blades. Generic inspection
        // magnification merges them into one opaque horizontal canopy slab.
        return 1.7
    case .Grapevine:
        // Full palmate grape blades will return after the network pass; keep
        // their botanical scale independent from the support-sized scaffold.
        return 2.0
    case .Oleander:
        // Preserve narrow whorled leaves instead of half-metre spear cards.
        return 1.15
    case .Bay_Laurel:
        // Laurel's authored sixteen-centimetre blades need no tree-scale
        // magnification; a small lift is enough for the catalog camera.
        return 1.7
    case .Myrtle:
        // Paired leaves no longer form oversized palmate stars, so restore
        // enough game-scale footprint for the fine staggered stations to knit
        // into Myrtle's dense evergreen crown.
        return 4.0
    case .Mastic:
        return 5.0
    case .Pomegranate:
        return 3.9
    case .Prickly_Pear:
        return 2.4
    case .Hydrangea_Bush, .Hydrangea_Tree:
        // Hydrangea already authors unusually broad leaves at botanical
        // dimensions. A restrained lift lets the corrected horizontal pairs
        // knit into a crown without turning them into half-metre paddles.
        return 1.24
    case .Agapanthus:
        // Strap leaves are already authored at their full botanical length.
        return 1.6
    case .Lavender:
        return 1.55
    case .Thyme:
        // The dedicated mat already emits close opposite pairs at every
        // runner link; generic inspection magnification made each tiny leaf
        // read as a broad groundcover paddle.
        return 3.2
    case .Pelargonium:
        // The dedicated mound is authored at patio-plant scale. Preserve the
        // broad round blades instead of shrinking them a second time here.
        return 1.05
    case .Strawberry_Tree:
        return 2.6
    case .Oriental_Plane:
        return 2.2
    case .European_Hackberry:
        return 2.2
    case .Sage:
        // Broad leaves are authored at full size; a restrained inspection
        // scale keeps opposite pairs legible without rebuilding giant stars.
        return 1.55
    }
    return 3.1
}

plant_generator_bounds_include :: proc(minimum, maximum: ^third_person.Vec3, point: third_person.Vec3) {
    minimum.x = min(minimum.x, point.x)
    minimum.y = min(minimum.y, point.y)
    minimum.z = min(minimum.z, point.z)
    maximum.x = max(maximum.x, point.x)
    maximum.y = max(maximum.y, point.y)
    maximum.z = max(maximum.z, point.z)
}

plant_generator_visual_bounds :: proc(
    species: plants.Species,
    generated: ^plants.Generated_Plant,
    scale, yaw: f32,
) -> (
    minimum, maximum: third_person.Vec3,
) {
    minimum = {math.F32_MAX, math.F32_MAX, math.F32_MAX}
    maximum = {-math.F32_MAX, -math.F32_MAX, -math.F32_MAX}
    // Preserve the complete generated skeleton even when a sparse plant has
    // no attachments near one of its extrema.
    for x in 0 ..< 2 {
        for y in 0 ..< 2 {
            for z in 0 ..< 2 {
                plant_generator_bounds_include(
                    &minimum,
                    &maximum,
                    plant_generator_point(
                        {},
                        {
                            x == 0 ? generated.bounds.minimum[0] : generated.bounds.maximum[0],
                            y == 0 ? generated.bounds.minimum[1] : generated.bounds.maximum[1],
                            z == 0 ? generated.bounds.minimum[2] : generated.bounds.maximum[2],
                        },
                        yaw,
                        scale,
                    ),
                )
            }
        }
    }
    presentation_scale := plant_generator_leaf_presentation_scale(species)
    for attachment in generated.attachments {
        if attachment.kind != .Leaf do continue
        variant := int(attachment.variant)
        if !plant_generator_leaf_mesh_ready[int(species)][variant] do continue
        mesh := &plant_generator_leaf_meshes[int(species)][variant]
        forward := linalg.normalize0(attachment.forward)
        up := linalg.normalize0(attachment.up)
        if species == .Prickly_Pear {
            pad_normal := lsystem.Vec3{attachment.forward[0], 0, attachment.forward[2]}
            if linalg.dot(pad_normal, pad_normal) < .001 do pad_normal = {attachment.up[0], 0, attachment.up[2]}
            if linalg.dot(pad_normal, pad_normal) < .001 do pad_normal = {0, 0, 1}
            forward = {0, 1, 0}
            up = linalg.normalize0(pad_normal)
        }
        right := linalg.normalize0(linalg.cross(forward, up))
        if linalg.dot(right, right) < .001 do right = {1, 0, 0}
        up = linalg.normalize0(linalg.cross(right, forward))
        for vertex in mesh.vertices {
            plant_generator_bounds_include(
                &minimum,
                &maximum,
                plant_generator_leaf_point(
                    {},
                    attachment.position,
                    right,
                    forward,
                    up,
                    vertex.position * presentation_scale,
                    yaw,
                    scale,
                ),
            )
        }
    }
    return
}

plant_generator_configure_camera :: proc(editor: ^Editor) {
    if editor == nil do return
    if plant_generator_climbing_garden {
        editor.camera_pose = third_person.camera_look_at({0, 7.2, 30.5}, {0, 3.15, 0})
    } else if plant_generator_succulent_garden {
        editor.camera_pose = third_person.camera_look_at({8.6, 6.4, 13.8}, {0, .85, 0})
    } else if plant_generator_isolated >= 0 && plant_generator_ready[plant_generator_isolated] {
        species := plants.Species(plant_generator_isolated)
        generated := &plant_generator_results[plant_generator_isolated].plant
        scale := plant_generator_display_scale(species)
        yaw := generated.habit == .Free_Standing ? f32(plant_generator_isolated) * .31 : f32(0)
        visual_minimum, visual_maximum := plant_generator_visual_bounds(species, generated, scale, yaw)
        width := max(visual_maximum.x - visual_minimum.x, visual_maximum.z - visual_minimum.z)
        height := visual_maximum.y - visual_minimum.y
        // Fit inspection captures directly to generated bounds in viewport
        // space. Wide silhouettes can use the capture's extra horizontal
        // room; tall silhouettes remain limited by its vertical field.
        radius := generated.habit == .Free_Standing ? plant_generator_frame_radius(width, height) : f32(4.8)
        focus_x := (visual_minimum.x + visual_maximum.x) * .5
        focus_z := (visual_minimum.z + visual_maximum.z) * .5
        focus_y := (visual_minimum.y + visual_maximum.y) * .5
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
    plant_generator_succulent_garden = target == "succulent-garden"
    plant_generator_climbing_garden = target == "climbing-garden" || target == "climbers"
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
    hydrangea_seed_prefix := "hydrangea-bush-seed-"
    if len(target) > len(hydrangea_seed_prefix) &&
       target[:len(hydrangea_seed_prefix)] == hydrangea_seed_prefix {
        parsed, ok := strconv.parse_int(target[len(hydrangea_seed_prefix):])
        if !ok || parsed < 0 {
            return false
        }
        plant_generator_seed = u64(parsed)
        plant_generator_isolated = int(plants.Species.Hydrangea_Bush)
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
    if target == "hydrangea-bush-medium" {
        plant_generator_isolated = int(plants.Species.Hydrangea_Bush)
        plant_generator_detail = .Medium
    }
    if target == "hydrangea-bush-far" {
        plant_generator_isolated = int(plants.Species.Hydrangea_Bush)
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
    if canvas2d.IsKeyPressed(.R) {
        plant_generator_seed += 1
        changed = true
    }
    // canvas2d currently exposes arrows but not bracket key codes; arrows are
    // the interactive aliases for the documented [ and ] maturity controls.
    if canvas2d.IsKeyPressed(.LEFT) {
        plant_generator_maturity = max(0, plant_generator_maturity - .1)
        changed = true
    }
    if canvas2d.IsKeyPressed(.RIGHT) {
        plant_generator_maturity = min(1, plant_generator_maturity + .1)
        changed = true
    }
    if canvas2d.IsKeyPressed(.ONE) {
        plant_generator_detail = .Near
        changed = true
    }
    if canvas2d.IsKeyPressed(.TWO) {
        plant_generator_detail = .Medium
        changed = true
    }
    if canvas2d.IsKeyPressed(.THREE) {
        plant_generator_detail = .Far
        changed = true
    }
    if canvas2d.IsKeyPressed(.FOUR) {
        plant_generator_isolated = -1
        plant_generator_succulent_garden = false
        plant_generator_climbing_garden = false
        changed = true
    }
    if canvas2d.IsKeyPressed(.UP) {
        plant_generator_succulent_garden = false
        plant_generator_climbing_garden = false
        plant_generator_isolated =
            plant_generator_isolated < 0 ? 0 : (plant_generator_isolated + 1) % plants.SPECIES_COUNT
        changed = true
    }
    if canvas2d.IsKeyPressed(.DOWN) {
        plant_generator_succulent_garden = false
        plant_generator_climbing_garden = false
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
    case .Golden_Barrel:
        return 2.6
    case .Agave, .Aloe:
        return 2.4
    case .Aeonium, .Jade_Plant:
        return 2.2
    case .Echeveria:
        return 3.0
    case .Stonecrop:
        return 4.4
    case .Blue_Chalk_Sticks:
        return 3.4
    case .Golden_Torch_Cactus:
        return 1.8
    case .Stone_Pine:
        return 1.35
    case .Bay_Laurel, .Carob, .Strawberry_Tree:
        return 1.55
    case .Holm_Oak, .Oriental_Plane, .European_Hackberry, .White_Poplar:
        return 1.25
    case .Bougainvillea:
        return 1.15
    case .Grapevine:
        return 1.0
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

plant_generator_colors :: proc(species: plants.Species) -> (wood, leaf, accent: canvas2d.Color) {
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
    case .Wisteria:
        return {104, 76, 54, 255}, {67, 110, 61, 255}, {145, 105, 190, 255}
    case .Climbing_Rose:
        return {105, 75, 52, 255}, {61, 112, 61, 255}, {220, 84, 112, 255}
    case .Hydrangea_Bush:
        return {92, 76, 56, 255}, {75, 119, 72, 255}, {111, 143, 207, 255}
    case .Hydrangea_Tree:
        return {104, 79, 56, 255}, {72, 116, 69, 255}, {204, 198, 224, 255}
    case .Agapanthus:
        return {85, 98, 63, 255}, {69, 121, 75, 255}, {105, 115, 205, 255}
    case .Star_Jasmine:
        return {91, 72, 51, 255}, {50, 105, 62, 255}, {239, 235, 213, 255}
    case .Holm_Oak:
        return {91, 72, 51, 255}, {55, 91, 52, 255}, {111, 91, 55, 255}
    case .Oriental_Plane:
        return {139, 111, 78, 255}, {86, 123, 66, 255}, {179, 148, 92, 255}
    case .European_Hackberry:
        return {105, 87, 65, 255}, {75, 117, 66, 255}, {92, 72, 51, 255}
    case .White_Poplar:
        return {119, 111, 99, 255}, {108, 132, 91, 255}, {178, 188, 166, 255}
    case .Golden_Barrel:
        return {92, 96, 53, 255}, {91, 142, 74, 255}, {220, 187, 68, 255}
    case .Agave:
        return {84, 94, 65, 255}, {91, 139, 121, 255}, {207, 183, 107, 255}
    case .Aloe:
        return {87, 92, 57, 255}, {75, 132, 83, 255}, {224, 119, 62, 255}
    case .Aeonium:
        return {92, 73, 56, 255}, {74, 54, 74, 255}, {224, 190, 72, 255}
    case .Echeveria:
        return {91, 89, 67, 255}, {119, 153, 143, 255}, {223, 141, 119, 255}
    case .Jade_Plant:
        return {91, 112, 65, 255}, {70, 139, 82, 255}, {239, 176, 180, 255}
    case .Stonecrop:
        return {89, 103, 63, 255}, {126, 157, 91, 255}, {218, 178, 77, 255}
    case .Blue_Chalk_Sticks:
        return {79, 99, 83, 255}, {102, 151, 157, 255}, {232, 224, 192, 255}
    case .Golden_Torch_Cactus:
        return {91, 96, 54, 255}, {72, 135, 72, 255}, {226, 187, 61, 255}
    }
    return {100, 75, 50, 255}, {65, 110, 60, 255}, {220, 160, 90, 255}
}

// A seed selects one cultivar colour for the whole specimen. Attachments only
// shift that colour's value, keeping neighboring blooms coherent in hue while
// avoiding a flat, machine-identical inflorescence.
plant_generator_flower_color :: proc(
    species: plants.Species,
    seed: u64,
    bloom_variant: u8,
    fallback: canvas2d.Color,
) -> canvas2d.Color {
    variety := int(seed % 4)
    base := fallback
    #partial switch species {
    case .Lemon, .Star_Jasmine, .Myrtle:
        colors := [4]canvas2d.Color {
            {246, 242, 222, 255},
            {255, 251, 235, 255},
            {235, 232, 215, 255},
            {250, 244, 229, 255},
        }
        base = colors[variety]
    case .Almond:
        colors := [4]canvas2d.Color {
            {245, 220, 220, 255},
            {236, 190, 199, 255},
            {250, 235, 228, 255},
            {224, 167, 184, 255},
        }
        base = colors[variety]
    case .Oleander:
        colors := [4]canvas2d.Color {
            {232, 126, 159, 255},
            {246, 190, 199, 255},
            {239, 231, 218, 255},
            {199, 74, 123, 255},
        }
        base = colors[variety]
    case .Bougainvillea:
        colors := [4]canvas2d.Color{{215, 57, 128, 255}, {180, 62, 151, 255}, {231, 92, 111, 255}, {196, 89, 174, 255}}
        base = colors[variety]
    case .Pelargonium:
        colors := [4]canvas2d.Color {
            {225, 67, 105, 255},
            {235, 112, 119, 255},
            {203, 47, 77, 255},
            {241, 174, 164, 255},
        }
        base = colors[variety]
    case .Climbing_Rose:
        colors := [4]canvas2d.Color {
            {222, 81, 106, 255},
            {241, 148, 153, 255},
            {235, 211, 193, 255},
            {190, 51, 76, 255},
        }
        base = colors[variety]
    case .Hydrangea_Bush, .Hydrangea_Tree:
        colors := [4]canvas2d.Color {
            {105, 139, 207, 255},
            {154, 119, 184, 255},
            {200, 133, 166, 255},
            {193, 202, 218, 255},
        }
        base = colors[variety]
    case .Agapanthus:
        colors := [4]canvas2d.Color {
            {99, 112, 204, 255},
            {126, 133, 218, 255},
            {173, 174, 225, 255},
            {232, 228, 235, 255},
        }
        base = colors[variety]
    case .Wisteria:
        colors := [4]canvas2d.Color {
            {143, 103, 188, 255},
            {175, 139, 207, 255},
            {205, 181, 220, 255},
            {231, 218, 226, 255},
        }
        base = colors[variety]
    case .Lavender:
        colors := [4]canvas2d.Color {
            {137, 99, 180, 255},
            {159, 119, 190, 255},
            {119, 105, 177, 255},
            {187, 151, 197, 255},
        }
        base = colors[variety]
    case .Thyme:
        colors := [4]canvas2d.Color{{190, 125, 174, 255}, {207, 146, 181, 255}, {180, 119, 165, 255}, {218, 166, 193, 255}}
        base = colors[variety]
    case .Sage:
        colors := [4]canvas2d.Color{{142, 102, 176, 255}, {128, 112, 181, 255}, {163, 123, 186, 255}, {184, 154, 199, 255}}
        base = colors[variety]
    }

    // Equal-channel offsets alter value without walking around the hue wheel.
    offsets := [4]int{-7, -2, 4, 8}
    offset := offsets[int(bloom_variant % 4)]
    return {
        u8(clamp(int(base.r) + offset, 0, 255)),
        u8(clamp(int(base.g) + offset, 0, 255)),
        u8(clamp(int(base.b) + offset, 0, 255)),
        base.a,
    }
}

plant_generator_leaf_color :: proc(species: plants.Species, variant: u8, fallback: canvas2d.Color) -> canvas2d.Color {
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
    if species == .Olive {
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
    }
    // General species still need restrained leaf-to-leaf pigment variation:
    // without it, dense canopies collapse into one uniform green volume. Keep
    // the authored fallback hue dominant and use the deterministic attachment
    // variant only for small chlorophyll/value shifts.
    switch variant % 4 {
    case 0:
        return fallback
    case 1:
        return color_lerp(fallback, {30, 69, 38, 255}, .10)
    case 2:
        return color_lerp(fallback, {150, 166, 93, 255}, .07)
    case 3:
        return color_lerp(fallback, {53, 99, 71, 255}, .08)
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

plant_generator_leaf_normal :: #force_inline proc(
    right, forward, up: lsystem.Vec3,
    normal: [3]f32,
    yaw: f32,
) -> third_person.Vec3 {
    local := linalg.normalize0(right * normal[0] + forward * normal[1] + up * normal[2])
    cosine, sine := math.cos(yaw), math.sin(yaw)
    return linalg.normalize0(third_person.Vec3 {
        local[0] * cosine - local[2] * sine,
        local[1],
        local[0] * sine + local[2] * cosine,
    })
}

plant_generator_draw_leaf :: proc(
    base: third_person.Vec3,
    species: plants.Species,
    attachment: plants.Attachment,
    yaw, display_scale: f32,
    color: canvas2d.Color,
) {
    variant := int(attachment.variant)
    if !plant_generator_leaf_mesh_ready[int(species)][variant] do return
    mesh := &plant_generator_leaf_meshes[int(species)][variant]
    presentation_scale := plant_generator_leaf_presentation_scale(species)

    forward := linalg.normalize0(attachment.forward)
    up := linalg.normalize0(attachment.up)
    if species == .Prickly_Pear {
        // Opuntia cladodes stand vertically. The dedicated skeleton authors
        // each pad's face normal in `up`; preserve it here so the lab matches
        // the runtime renderer instead of applying a second variant rotation.
        pad_normal := lsystem.Vec3{attachment.forward[0], 0, attachment.forward[2]}
        if linalg.dot(pad_normal, pad_normal) < .001 {
            pad_normal = {attachment.up[0], 0, attachment.up[2]}
        }
        if linalg.dot(pad_normal, pad_normal) < .001 do pad_normal = {0, 0, 1}
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
        face_normal := linalg.normalize0(linalg.cross(b - a, c - a))
        vertex_a := mesh.vertices[mesh.indices[first + 0]]
        vertex_b := mesh.vertices[mesh.indices[first + 1]]
        vertex_c := mesh.vertices[mesh.indices[first + 2]]
        normal_a := plant_generator_leaf_normal(right, forward, up, vertex_a.normal, yaw)
        normal_b := plant_generator_leaf_normal(right, forward, up, vertex_b.normal, yaw)
        normal_c := plant_generator_leaf_normal(right, forward, up, vertex_c.normal, yaw)
        // Wind bends positions after the rigid leaf transform. Keep authored
        // smooth normals on the deformed triangle's visible hemisphere.
        if linalg.dot(normal_a, face_normal) < 0 do normal_a = -normal_a
        if linalg.dot(normal_b, face_normal) < 0 do normal_b = -normal_b
        if linalg.dot(normal_c, face_normal) < 0 do normal_c = -normal_c
        uv_a := mesh.vertices[mesh.indices[first + 0]].uv
        uv_b := mesh.vertices[mesh.indices[first + 1]].uv
        uv_c := mesh.vertices[mesh.indices[first + 2]].uv
        world_triangle_leaf_textured(
            a,
            b,
            c,
            color,
            color,
            color,
            normal_a,
            normal_b,
            normal_c,
            uv_a,
            uv_b,
            uv_c,
            u32(attachment.leaf.shape),
        )
        world_triangle_leaf_textured(
            c,
            b,
            a,
            color,
            color,
            color,
            -normal_c,
            -normal_b,
            -normal_a,
            uv_c,
            uv_b,
            uv_a,
            u32(attachment.leaf.shape),
        )
    }
}

plant_generator_draw_flower :: proc(
    position: third_person.Vec3,
    species: plants.Species,
    attachment: plants.Attachment,
    display_scale: f32,
    color: canvas2d.Color,
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
    if (species == .Agapanthus ||
           species == .Lavender ||
           species == .Thyme ||
           species == .Sage ||
           species == .Pelargonium ||
           species == .Star_Jasmine ||
           species == .Wisteria ||
           species == .Climbing_Rose ||
           species == .Hydrangea_Bush ||
           species == .Hydrangea_Tree) &&
       plant_generator_maturity >= .90 {
        // A mature terminal umbel opens as a coordinated head. Per-anchor
        // random lifecycle stages leave most of its nine display florets as
        // sub-pixel buds even in the 100% maturity inspection state.
        stage_index = 3
    }
    if !plant_generator_flower_mesh_ready[int(species)][stage_index] do return
    mesh := &plant_generator_flower_meshes[int(species)][stage_index]
    outward := linalg.normalize0(attachment.forward)
    up := linalg.normalize0(attachment.up)
    right := linalg.normalize0(linalg.cross(up, outward))
    if linalg.dot(right, right) < .001 do right = {1, 0, 0}
    up = linalg.normalize0(linalg.cross(outward, right))
    if species == .Hydrangea_Bush || species == .Hydrangea_Tree {
        head_open_stages := [4]f32{.42, .62, .82, 1}
        // Closed lifecycle meshes have a deliberately tight petal profile.
        // Hydrangea still needs those many buds to register collectively as
        // a compact head before opening, so compensate at the floret level
        // and taper the correction away by full bloom.
        floret_stage_scale := [4]f32{1.55, 1.25, 1.08, 1}
        head_open := head_open_stages[stage_index]
        maturity_scale := .62 + plant_generator_maturity * .38
        cluster_base_count, cluster_stage_step, cluster_floret_scale := 32, 16, f32(.30)
        switch plant_generator_detail {
        case .Near:
        case .Medium:
            cluster_base_count, cluster_stage_step, cluster_floret_scale = 24, 12, .34
        case .Far:
            // Retain enough discrete sites to avoid large Fibonacci gaps;
            // modestly enlarged florets preserve coverage with 52 rather than
            // Near's 80 samples.
            cluster_base_count, cluster_stage_step, cluster_floret_scale = 16, 12, .39
        }
        cluster_config := flower_mesh.cluster_defaults(.Ball)
        // Mopheads read as a mass of many small sterile florets. Preserve the
        // authored head envelope while increasing overlap instead of making
        // a sparse cluster from a handful of oversized blossoms.
        cluster_config.flower_count = cluster_base_count + stage_index * cluster_stage_step
        cluster_config.radius = (.078 + f32(attachment.variant) * .005) * head_open * maturity_scale
        cluster_config.height = (.052 + f32(attachment.variant) * .002) * head_open * maturity_scale
        cluster_config.floret_scale =
            cluster_floret_scale * floret_stage_scale[stage_index] *
            (.92 + f32(attachment.variant) * .045) * maturity_scale
        cluster_config.scale_variation = .10
        // Variant alone only supplies four phases, making repeated heads
        // visibly share the same Fibonacci floret pattern. Fold the authored
        // terminal position into the phase so every mophead remains stable
        // but receives its own arrangement.
        cluster_config.phase =
            f32(attachment.variant) * .71 + attachment.position[0] * 17.3 + attachment.position[2] * 23.1
        cluster := flower_mesh.generate_cluster(cluster_config)
        for instance, floret_index in cluster.instances[:cluster.count] {
            // Neighboring sterile florets catch light and mature at slightly
            // different rates. Stable micro-variation keeps a dense mophead
            // from collapsing into one flat blue material patch.
            tone := (floret_index * 7 + int(attachment.variant) * 3) % 9 - 4
            warm := (floret_index + int(attachment.variant) * 5) % 11 == 0
            floret_color := canvas2d.Color {
                u8(clamp(int(color.r) + tone * 2 + (warm ? 5 : 0), 0, 255)),
                u8(clamp(int(color.g) + tone + (warm ? 2 : 0), 0, 255)),
                u8(clamp(int(color.b) + tone * 2 + (warm ? 4 : 0), 0, 255)),
                color.a,
            }
            floret_position :=
                position + right * instance.position[0] + up * instance.position[1] + outward * instance.position[2]
            floret_outward := linalg.normalize0(
                right * instance.normal[0] + up * instance.normal[1] + outward * instance.normal[2],
            )
            floret_right := right - floret_outward * linalg.dot(right, floret_outward)
            if linalg.dot(floret_right, floret_right) < .001 {
                floret_right = up - floret_outward * linalg.dot(up, floret_outward)
            }
            floret_right = linalg.normalize0(floret_right)
            floret_up := linalg.normalize0(linalg.cross(floret_outward, floret_right))
            cosine, sine := math.cos(instance.rotation), math.sin(instance.rotation)
            rotated_right := linalg.normalize0(floret_right * cosine + floret_up * sine)
            rotated_up := linalg.normalize0(-floret_right * sine + floret_up * cosine)
            for first := 0; first + 2 < mesh.index_count; first += 3 {
                points: [3]third_person.Vec3
                normals: [3]third_person.Vec3
                for point_index in 0 ..< 3 {
                    vertex := mesh.vertices[mesh.indices[first + point_index]]
                    points[point_index] =
                        floret_position +
                        rotated_right * vertex.position[0] * instance.scale +
                        rotated_up * vertex.position[1] * instance.scale +
                        floret_outward * vertex.position[2] * instance.scale
                    normals[point_index] = linalg.normalize0(
                        rotated_right * vertex.normal[0] +
                        rotated_up * vertex.normal[1] +
                        floret_outward * vertex.normal[2],
                    )
                }
                world_triangle_smooth_lit(
                    points[0],
                    points[1],
                    points[2],
                    normals[0],
                    normals[1],
                    normals[2],
                    floret_color,
                    floret_color,
                    floret_color,
                    .88,
                )
            }
        }
        return
    }
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
        scale = .55
        floret_count = 7
    } else if species == .Thyme {
        // Thyme flowers are tiny lip-like whorls tucked into the mat, not
        // full-size garden corollas. A compact three-floret cluster keeps the
        // bloom readable without obscuring the creeping foliage beneath it.
        scale = .16
        floret_count = 3
    } else if species == .Sage {
        // Sage flowers climb in spaced whorls above the silver leaf mound.
        // A narrow vertical run reads as a flower spike; one large generic
        // corolla reads as purple disks pasted throughout the shrub.
        scale = .50
        floret_count = 5
    } else if species == .Pelargonium {
        // One terminal marker represents a compact rounded umbel.
        scale = .34
        floret_count = 7
    } else if species == .Star_Jasmine {
        // Small white pinwheels gather into loose clusters along trained vines.
        // The pale support consumes their edges at the standard camera, so
        // let each attachment represent a five-flower cyme rather than a few
        // isolated sub-pixel corollas.
        scale = 2.0
        floret_count = 5
    } else if species == .Wisteria {
        // One attachment stands for a hanging raceme, not one large blossom.
        scale = 1.0
        floret_count = 7
    } else if species == .Climbing_Rose {
        // Loose terminal rose clusters punctuate the trained cane network.
        scale = 2.0
        floret_count = 3
    } else if species == .Oleander {
        // Oleander blooms collect into loose terminal cymes. Several modest
        // corollas read as a cluster without masking the narrow leaves.
        scale = .95
        floret_count = 3
    } else if species == .Agapanthus {
        // One authored terminal marker represents a spherical umbel of many
        // small blue trumpets, not a single enlarged flower.
        scale = .50
        floret_count = 9
    }
    for floret_index in 0 ..< floret_count {
        floret_position := position
        floret_right, floret_up, floret_outward := right, up, outward
        if species == .Lavender {
            floret_position.y += (3 - f32(floret_index)) * .024
            floret_position += right * (floret_index % 2 == 0 ? f32(-.018) : f32(.018))
        } else if species == .Thyme {
            floret_position.y += (.5 - f32(floret_index)) * .026
            floret_position += right * (floret_index % 2 == 0 ? f32(-.012) : f32(.012))
        } else if species == .Sage {
            floret_position.y += (1.5 - f32(floret_index)) * .045
            floret_position += right * (floret_index % 2 == 0 ? f32(-.014) : f32(.014))
        } else if species == .Pelargonium {
            if floret_index > 0 {
                angle := f32(floret_index - 1) * math.PI * 2 / f32(floret_count - 1)
                floret_position += right * math.cos(angle) * .045
                floret_position += outward * math.sin(angle) * .045
                floret_position += up * (floret_index % 2 == 0 ? f32(.018) : f32(-.010))
            }
        } else if species == .Star_Jasmine {
            if floret_index > 0 {
                angle := f32(floret_index - 1) * math.PI * .5
                floret_position += right * f32(math.cos(f64(angle))) * .030
                floret_position.y += f32(math.sin(f64(angle))) * .030
            }
        } else if species == .Wisteria {
            floret_position.y -= f32(floret_index) * .035
            floret_position += right * (floret_index % 2 == 0 ? f32(-.016) : f32(.016))
        } else if species == .Climbing_Rose {
            floret_position.y += floret_index == 0 ? f32(.022) : f32(-.010)
            if floret_index > 0 {
                floret_position += right * (floret_index == 1 ? f32(-.030) : f32(.030))
            }
        } else if species == .Oleander {
            floret_position.y += (floret_index == 0 ? f32(.035) : f32(-.018))
            if floret_index > 0 {
                floret_position += right * (floret_index == 1 ? f32(-.055) : f32(.055))
            }
        } else if species == .Agapanthus {
            if floret_index > 0 {
                ring_index := floret_index - 1
                angle := f32(ring_index % 4) * math.PI * .5 + f32(ring_index / 4) * .37
                radius := ring_index < 4 ? f32(.050) : f32(.040)
                vertical := ring_index < 4 ? f32(.018) : f32(-.021)
                offset := right * math.cos(angle) * radius + outward * math.sin(angle) * radius + up * vertical
                floret_position += offset
                // Turn each trumpet away from the center of the umbel. A
                // shared plane makes the cluster read as one flat bouquet.
                floret_outward = linalg.normalize0(offset)
                reference := math.abs(floret_outward.y) < .9 ? third_person.Vec3{0, 1, 0} : third_person.Vec3{1, 0, 0}
                floret_right = linalg.normalize0(linalg.cross(reference, floret_outward))
                floret_up = linalg.normalize0(linalg.cross(floret_outward, floret_right))
            }
        }
        for first := 0; first + 2 < mesh.index_count; first += 3 {
            points: [3]third_person.Vec3
            normals: [3]third_person.Vec3
            for point_index in 0 ..< 3 {
                vertex := mesh.vertices[mesh.indices[first + point_index]]
                points[point_index] =
                    floret_position +
                    floret_right * vertex.position[0] * scale +
                    floret_up * vertex.position[1] * scale +
                    floret_outward * vertex.position[2] * scale
                normals[point_index] = linalg.normalize0(
                    floret_right * vertex.normal[0] + floret_up * vertex.normal[1] + floret_outward * vertex.normal[2],
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
    color: canvas2d.Color,
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
    color: canvas2d.Color,
) {
    if !plant_generator_branch_mesh_ready[index] do return
    mesh := &plant_generator_branch_meshes[index]
    bark := plant_bark.profile(plants.Species(index))
    bark_detail_strength := plant_generator_detail == .Near ? f32(1) :
                            plant_generator_detail == .Medium ? f32(.52) : f32(.24)
    cosine, sine := math.cos(yaw), math.sin(yaw)
    for first := 0; first + 2 < len(mesh.indices); first += 3 {
        points: [3]third_person.Vec3
        normals: [3]third_person.Vec3
        uvs: [3][2]f32
        bark_color := canvas2d.Color{bark.base_color[0], bark.base_color[1], bark.base_color[2], color.a}
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
            uvs[point_index] = {
                vertex.bark_uv[0] * bark.scale,
                vertex.bark_uv[1] * bark.scale,
            }
        }
        // A cylindrical ring stores [0, 1) once. Repair triangles crossing
        // that seam locally so interpolation takes the short route through 1
        // rather than smearing backward across the whole circumference.
        minimum_u, maximum_u := uvs[0].x, uvs[0].x
        for point_index in 1 ..< 3 {
            minimum_u = min(minimum_u, uvs[point_index].x)
            maximum_u = max(maximum_u, uvs[point_index].x)
        }
        if maximum_u - minimum_u > bark.scale * .5 {
            for point_index in 0 ..< 3 {
                if uvs[point_index].x < bark.scale * .5 {
                    uvs[point_index].x += bark.scale
                }
            }
        }
        world_triangle_bark(
            points[0],
            points[1],
            points[2],
            normals[0],
            normals[1],
            normals[2],
            bark_color, bark_color, bark_color,
            uvs[0], uvs[1], uvs[2],
            f32(int(bark.pattern)), bark.roughness, bark_detail_strength,
        )
    }
}

plant_generator_draw_barrel_cactus :: proc(base: third_person.Vec3, yaw, display_scale: f32, color: canvas2d.Color) {
    if !plant_generator_barrel_mesh_ready do return
    cosine, sine := math.cos(yaw), math.sin(yaw)
    for first := 0; first + 2 < len(plant_generator_barrel_mesh.indices); first += 3 {
        points: [3]third_person.Vec3
        normals: [3]third_person.Vec3
        colors: [3]canvas2d.Color
        for corner in 0 ..< 3 {
            vertex := plant_generator_barrel_mesh.vertices[plant_generator_barrel_mesh.indices[first + corner]]
            points[corner] = plant_generator_point(base, vertex.position, yaw, display_scale)
            normals[corner] = linalg.normalize0(
                third_person.Vec3 {
                    vertex.normal[0] * cosine - vertex.normal[2] * sine,
                    vertex.normal[1],
                    vertex.normal[0] * sine + vertex.normal[2] * cosine,
                },
            )
            ridge_light := .94 + f32(vertex.rib % 2) * .08
            colors[corner] = {
                r = u8(clamp(f32(color.r) * ridge_light, 0, 255)),
                g = u8(clamp(f32(color.g) * ridge_light, 0, 255)),
                b = u8(clamp(f32(color.b) * ridge_light, 0, 255)),
                a = color.a,
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
            .82,
        )
    }
}

plant_generator_stage_color :: proc(color: canvas2d.Color, stage: plants.Attachment_Stage) -> canvas2d.Color {
    green := canvas2d.Color{91, 132, 67, color.a}
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
    shadow_first := len(world_renderer.vertices)
    if species == .Golden_Barrel {
        plant_generator_draw_barrel_cactus(base, yaw, display_scale, leaf_color)
    }
    // Opuntia cladodes are the persistent structure; its tiny internal
    // topology exists for generation invariants, not as visible brown wood.
    if species == .Grapevine {
        // Draw every routed cane directly because the generic welded hull can
        // discard extremely fine spans at multi-way trellis junctions. Use
        // the production bark path rather than the old diagnostic orange
        // tubes so even the fine network retains grapevine's flaky identity.
        bark := plant_bark.profile(species)
        // These canes are presentation-thickened but remain only a few
        // pixels wide. Full trunk-strength relief alternates with each short
        // segment frame, so retain a quieter peeling signal here.
        bark_detail_strength := plant_generator_detail == .Near ? f32(.48) :
                                plant_generator_detail == .Medium ? f32(.25) : f32(.12)
        for segment in result.segments {
            display_segment := segment
            // Presentation-scale minimums keep young trained shoots legible
            // against the pale wall. Apply them to a copy so generation data
            // and production-world radii remain botanically authoritative.
            display_segment.radius_start = max(
                display_segment.radius_start,
                f32(.024) / max(display_scale, f32(.001)),
            )
            display_segment.radius_end = max(
                display_segment.radius_end,
                f32(.014) / max(display_scale, f32(.001)),
            )
            world_generated_bark_segment(
                display_segment,
                bark,
                plant_generator_seed,
                base,
                display_scale,
                yaw,
                0,
                bark_detail_strength,
                0,
                -1,
                false,
                false,
            )
        }
    } else if species != .Prickly_Pear &&
       species != .Golden_Barrel &&
       species != .Agave &&
       species != .Aloe &&
       species != .Echeveria &&
       species != .Stonecrop &&
       species != .Blue_Chalk_Sticks &&
       species != .Golden_Torch_Cactus {
        plant_generator_draw_branch_hull(index, base, yaw, display_scale, wood)
    }
    for attachment in result.attachments {
        if species == .Golden_Barrel do continue
        position := plant_generator_point(base, attachment.position, yaw, display_scale)
        color := attachment.kind == .Leaf || attachment.kind == .Tendril ? leaf_color : accent
        if attachment.kind == .Flower {
            color = plant_generator_flower_color(species, plant_generator_seed, attachment.variant, color)
        }
        if species == .Italian_Cypress && attachment.kind == .Fruit {
            // Young cones stay olive green; older variants dry toward warm
            // woody brown. Both remain distinct against the blue-green crown.
            color = attachment.variant < 2 ? canvas2d.Color{119, 128, 68, 255} : canvas2d.Color{164, 117, 66, 255}
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
    world_register_shadow_caster(shadow_first)
}

plant_generator_draw_succulent_garden :: proc() {
    sand := canvas2d.Color{151, 126, 82, 255}
    gravel := canvas2d.Color{182, 164, 121, 255}
    limestone := canvas2d.Color{173, 166, 143, 255}
    dark_stone := canvas2d.Color{105, 101, 88, 255}
    world_box({0, -.18, 0}, {24, .34, 16}, sand)
    // Overlapping gravel pads soften the rectangular lab floor into a dry
    // garden bed while retaining deterministic, inexpensive primitives.
    world_ellipsoid_rotated({-3.7, .015, -.8}, 4.6, .10, 4.0, -.18, gravel)
    world_ellipsoid_rotated({2.8, .018, .4}, 5.0, .11, 4.1, .12, gravel)
    world_ellipsoid_rotated({.2, .020, -2.8}, 4.2, .10, 2.7, .05, gravel)

    // A central barrel anchors the composition; asymmetrical rosettes and an
    // opuntia screen create three distinct height bands around it.
    plant_generator_draw_result(int(plants.Species.Golden_Barrel), {0, .10, .15})
    plant_generator_draw_result(int(plants.Species.Agave), {-3.55, .08, -1.45})
    plant_generator_draw_result(int(plants.Species.Agave), {3.65, .08, 1.60})
    plant_generator_draw_result(int(plants.Species.Aloe), {-1.90, .08, 2.35})
    plant_generator_draw_result(int(plants.Species.Aloe), {2.25, .08, -2.35})
    plant_generator_draw_result(int(plants.Species.Prickly_Pear), {4.85, .08, -1.05})
    plant_generator_draw_result(int(plants.Species.Aeonium), {-5.15, .08, .35})
    plant_generator_draw_result(int(plants.Species.Echeveria), {1.15, .08, 3.15})
    plant_generator_draw_result(int(plants.Species.Jade_Plant), {-3.55, .08, 2.65})
    plant_generator_draw_result(int(plants.Species.Stonecrop), {3.85, .08, -3.05})
    plant_generator_draw_result(int(plants.Species.Blue_Chalk_Sticks), {-.55, .08, -3.25})
    plant_generator_draw_result(int(plants.Species.Golden_Torch_Cactus), {5.55, .08, 2.05})

    rock_positions := [9]third_person.Vec3 {
        {-5.1, .13, -2.8},
        {-4.9, .10, 1.35},
        {-3.0, .12, 3.45},
        {-1.2, .09, -3.65},
        {1.25, .12, 3.72},
        {3.0, .10, -3.48},
        {4.75, .13, 2.85},
        {5.55, .09, .55},
        {.72, .08, -1.35},
    }
    for position, index in rock_positions {
        radius := .28 + f32(index % 3) * .09
        color := index % 4 == 0 ? dark_stone : limestone
        world_ellipsoid_rotated(position, radius * 1.35, radius * .62, radius, f32(index) * .73, color)
    }
}

plant_generator_draw_climbing_garden :: proc() {
    lawn := canvas2d.Color{105, 126, 77, 255}
    path := canvas2d.Color{171, 157, 126, 255}
    border := canvas2d.Color{113, 91, 62, 255}
    world_box({0, -.18, 0}, {50, .34, 12}, lawn)
    world_box({0, .015, 3.15}, {47, .05, 2.0}, path)

    // A single nursery promenade keeps every support at the same scale and
    // distance, making branching habits directly comparable without one wall
    // hiding another.
    species := [5]plants.Species{.Bougainvillea, .Grapevine, .Wisteria, .Climbing_Rose, .Star_Jasmine}
    positions := [5]third_person.Vec3{{-18.8, 0, 0}, {-9.4, 0, 0}, {0, 0, 0}, {9.4, 0, 0}, {18.8, 0, 0}}
    for plant_species, index in species {
        base := positions[index]
        world_box({base.x, .035, base.z + .42}, {8.5, .07, 1.25}, border)
        plant_generator_draw_result(int(plant_species), base)
    }
}

world_plant_generator_lab :: proc(_: ^Editor) {
    if plant_generator_climbing_garden {
        plant_generator_draw_climbing_garden()
        return
    }
    if plant_generator_succulent_garden {
        plant_generator_draw_succulent_garden()
        return
    }
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
    panel := canvas2d.Rectangle{24, 24, 560, 126}
    canvas2d.DrawRectangleRounded(panel, .14, 8, {19, 31, 27, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .14, 8, 1, {111, 146, 111, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "ADRIATIC PLANT GENERATOR", {38, 38}, 18, 1, {232, 224, 189, 255})
    detail_name := plant_generator_detail == .Near ? "NEAR" : plant_generator_detail == .Medium ? "MEDIUM" : "FAR"
    summary := fmt.ctprintf(
        "SEED %d  /  MATURITY %.0f%%  /  %s",
        plant_generator_seed,
        plant_generator_maturity * 100,
        detail_name,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, summary, {38, 66}, 13, 1, {174, 207, 160, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "R SEED   LEFT/RIGHT MATURITY   UP/DOWN SPECIES   1/2/3 DETAIL   4 GALLERY",
        {38, 91},
        11,
        1,
        {184, 191, 174, 255},
    )
    if plant_generator_climbing_garden {
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            "CLIMBING GARDEN  /  BOUGAINVILLEA  GRAPEVINE  WISTERIA  CLIMBING ROSE  STAR JASMINE",
            {38, 116},
            10,
            1,
            {216, 194, 151, 255},
        )
    } else if plant_generator_succulent_garden {
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            "SUCCULENT GARDEN  /  CACTI  ROSETTES  JADE  STONECROP  CHALK STICKS",
            {38, 116},
            10,
            1,
            {216, 194, 151, 255},
        )
    } else if plant_generator_isolated >= 0 {
        isolated_label := fmt.ctprintf("%s", plants.species_name(plants.Species(plant_generator_isolated)))
        canvas2d.DrawTextEx(canvas2d.Font{}, isolated_label, {38, 116}, 10, 1, {216, 194, 151, 255})
    } else {
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            "OLIVE  CYPRESS  FIG  LEMON  /  POMEGRANATE  ALMOND  OLEANDER  ROSEMARY  /  BOUGAINVILLEA  GRAPEVINE",
            {38, 116},
            10,
            1,
            {216, 194, 151, 255},
        )
    }
}
