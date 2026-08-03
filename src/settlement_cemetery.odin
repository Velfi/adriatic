package main

import architecture "../packages/architecture"
import cemeteries "../packages/cemeteries"
import plants "../packages/plants"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

SETTLEMENT_CEMETERY_GROUP_TAG :: u64(0xCE4E_7E12_0000_0000)
SETTLEMENT_CEMETERY_GROUP_MASK :: u64(0xffff_ffff_0000_0000)

settlement_cemetery_structure_is_reservation :: proc(structure: terrain.Structure) -> bool {
    return structure.group_id & SETTLEMENT_CEMETERY_GROUP_MASK == SETTLEMENT_CEMETERY_GROUP_TAG
}

Settlement_Cemetery :: struct {
    plan:     cemeteries.Plan,
    origin:   [2]f32,
    rotation: f32,
    ground_y: f32,
    valid:    bool,
}

settlement_cemetery_dimensions :: proc(scale: Settlement_Scale) -> (width, depth, density: f32) {
    switch scale {
    case .City:
        return 20, 26, .78
    case .Town:
        return 16, 21, .64
    case .Village:
        return 12, 16, .48
    }
    return 12, 16, .48
}

settlement_cemetery_outer_radius :: proc(plan: ^Settlement_Plan) -> f32 {
    radius := f32(0)
    for cell in plan.macro_cells[:plan.macro_cell_count] {
        dx := cell.center[0] - plan.request.center[0]
        dz := cell.center[1] - plan.request.center[1]
        radius = max(radius, f32(math.sqrt(f64(dx * dx + dz * dz))) + cell.radius)
    }
    if radius <= 0 do radius = plan.request.radius * .42
    return radius
}

settlement_cemetery_built_radius :: proc(plan: ^Settlement_Plan) -> f32 {
    if plan == nil do return 0
    radius := f32(0)
    for site in plan.sites[:plan.site_count] {
        if !site.accepted || (site.kind != .Ordinary && site.kind != .Landmark && site.kind != .Ruin) {
            continue
        }
        center := [2]f32{site.structure.center_x, site.structure.center_z}
        extent :=
            f32(
                math.sqrt(
                    f64(site.structure.width * site.structure.width + site.structure.depth * site.structure.depth),
                ),
            ) *
            .5
        radius = max(radius, linalg.length(center - plan.request.center) + extent)
    }
    return radius
}

settlement_cemetery_site_relief :: proc(
    project: ^terrain.Project,
    x, z, width, depth, rotation: f32,
) -> (
    center_y, relief: f32,
) {
    center_y = terrain.sample_surface_height(project, 0, x, z)
    for side_x in -1 ..= 1 {
        for side_z in -1 ..= 1 {
            if side_x == 0 && side_z == 0 do continue
            sample_x, sample_z := world_rotate_xz(x, z, f32(side_x) * width * .46, f32(side_z) * depth * .46, rotation)
            sample_y := terrain.sample_surface_height(project, 0, sample_x, sample_z)
            relief = max(relief, math.abs(sample_y - center_y))
        }
    }
    return
}

settlement_cemetery_access_clear :: proc(editor: ^Editor, x, z, width, depth, rotation: f32) -> bool {
    approach_length := f32(10)
    approach_x, approach_z := world_rotate_xz(x, z, 0, -depth * .5 - approach_length * .5, rotation)
    empty_city: architecture.City_Plan
    if !settlement_structure_clear(
        &editor.project,
        &empty_city,
        approach_x,
        approach_z,
        2.1,
        approach_length,
        rotation,
        .8,
    ) {
        return false
    }
    if !settlement_structure_footprint_on_land(
        &editor.project,
        approach_x,
        approach_z,
        2.1,
        approach_length,
        rotation,
        .6,
    ) {
        return false
    }
    _, relief := settlement_cemetery_site_relief(
        &editor.project,
        approach_x,
        approach_z,
        2.1,
        approach_length,
        rotation,
    )
    return relief <= .8
}

settlement_cemetery_derive :: proc(editor: ^Editor) -> Settlement_Cemetery {
    result: Settlement_Cemetery
    if editor == nil do return result
    settlement := &editor.settlement_plan
    if settlement.site_count == 0 || settlement.macro_cell_count == 0 do return result
    width, depth, density := settlement_cemetery_dimensions(settlement.request.scale)
    style := settlement.request.region == .Aegean ? cemeteries.Style.Classical_Aegean : .Adriatic_Medieval
    for structure in editor.project.structures[:editor.project.structure_count] {
        if !settlement_cemetery_structure_is_reservation(structure) do continue
        result.plan = cemeteries.generate(
            settlement.request.seed ~ u32(0xCE4E7E12),
            {width = structure.width, depth = structure.depth, density = density, style = style},
        )
        result.origin = {structure.center_x, structure.center_z}
        result.rotation = structure.rotation
        result.ground_y = structure.base_y
        result.valid = result.plan.valid
        return result
    }
    outer_radius := settlement_cemetery_outer_radius(settlement)
    if settlement.request.scale == .Town {
        built_radius := settlement_cemetery_built_radius(settlement)
        if built_radius > 0 do outer_radius = min(outer_radius, built_radius)
    }
    seed := settlement.request.seed ~ u32(0xCE4E7E12)
    angle_offset := f32(cemeteries.mix(seed) & 0xffff) / f32(0xffff) * math.PI * 2
    best_approach_distance := f32(1e9)
    best_x, best_z, best_rotation, best_ground_y := f32(0), f32(0), f32(0), f32(0)
    best_found := false
    for candidate in 0 ..< 20 {
        angle := angle_offset + f32(candidate) * math.PI * 2 / 20
        outward_x, outward_z := math.sin(angle), math.cos(angle)
        edge_gap := settlement.request.scale == .Town ? f32(5) : f32(9)
        distance := outer_radius + depth * .5 + edge_gap + f32(candidate / 10) * 8
        x := settlement.request.center[0] + outward_x * distance
        z := settlement.request.center[1] + outward_z * distance
        rotation := angle
        if !settlement_park_site_clear(&editor.project, x, z, width, depth) do continue
        if !settlement_structure_footprint_on_land(&editor.project, x, z, width, depth, rotation, 1.2) do continue
        if !settlement_cemetery_access_clear(editor, x, z, width, depth, rotation) do continue
        ground_y, relief := settlement_cemetery_site_relief(&editor.project, x, z, width, depth, rotation)
        if ground_y <= editor.project.sea_level + .5 || relief > 1.05 do continue
        if settlement.request.scale == .Town {
            approach_x, approach_z := world_rotate_xz(x, z, 0, -depth * .5 - 5, rotation)
            approach_distance := settlement_nearest_committed_road_distance(&editor.project, {approach_x, approach_z})
            if approach_distance > 32 || approach_distance >= best_approach_distance do continue
            best_approach_distance = approach_distance
            best_x, best_z, best_rotation, best_ground_y = x, z, rotation, ground_y
            best_found = true
            continue
        }
        result.plan = cemeteries.generate(seed, {width = width, depth = depth, density = density, style = style})
        result.origin = {x, z}
        result.rotation = rotation
        result.ground_y = ground_y
        result.valid = result.plan.valid
        return result
    }
    if best_found {
        result.plan = cemeteries.generate(seed, {width = width, depth = depth, density = density, style = style})
        result.origin = {best_x, best_z}
        result.rotation = best_rotation
        result.ground_y = best_ground_y
        result.valid = result.plan.valid
    }
    return result
}

settlement_cemetery_reserve :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    for structure in editor.project.structures[:editor.project.structure_count] {
        if settlement_cemetery_structure_is_reservation(structure) do return true
    }
    site := settlement_cemetery_derive(editor)
    if !site.valid do return false
    reservation := terrain.structure_make(
        site.origin[0],
        site.origin[1],
        site.plan.width,
        site.plan.depth,
        site.ground_y,
        .01,
    )
    reservation.kind = .Foliage
    reservation.rotation = site.rotation
    reservation.group_id = SETTLEMENT_CEMETERY_GROUP_TAG | u64(editor.settlement_plan.request.seed)
    return terrain.add_structure(&editor.project, reservation) >= 0
}

settlement_cemetery_world_point :: proc(site: Settlement_Cemetery, local_x, local_z: f32) -> (x, z: f32) {
    return world_rotate_xz(site.origin[0], site.origin[1], local_x, local_z, site.rotation)
}

world_settlement_cemetery :: proc(editor: ^Editor, include_stable := true, include_trees := true) {
    site := settlement_cemetery_derive(editor)
    if !site.valid do return
    if !world_renderer.retained_patio_rebuilding &&
       !world_sphere_in_view(
               editor,
               {site.origin[0], site.ground_y + 2, site.origin[1]},
               max(site.plan.width, site.plan.depth),
               2,
           ) {
        return
    }

    if !include_stable {
        if !include_trees do return
        for tree, tree_index in site.plan.trees[:site.plan.tree_count] {
            x, z := settlement_cemetery_world_point(site, tree.x, tree.z)
            y := terrain.sample_surface_height(&editor.project, 0, x, z)
            species := tree_index % 4 == 1 ? plants.Species.Olive : .Italian_Cypress
            _ = world_generated_plant(
                species,
                u64(site.plan.seed) << 32 ~ u64(tree_index + 1),
                third_person.Vec3{x, y, z},
                species == .Olive ? f32(.72) : f32(.78),
                site.rotation + f32(tree_index) * .73,
                .Free_Standing,
                nil,
                .Medium,
                0,
                .86,
            )
        }
        return
    }

    wall_color :=
        site.plan.style == .Adriatic_Medieval ? canvas2d.Color{175, 166, 143, 255} : canvas2d.Color{151, 149, 139, 255}
    path_color := canvas2d.Color{135, 126, 108, 255}
    path_x, path_z := settlement_cemetery_world_point(site, 0, 0)
    path_y := terrain.sample_surface_height(&editor.project, 0, path_x, path_z)
    world_box_rotated(
        {path_x, path_y + .025, path_z},
        {site.plan.path_width, .05, site.plan.depth - 1.2},
        site.rotation,
        path_color,
    )

    half_width, half_depth := site.plan.width * .5, site.plan.depth * .5
    approach_x, approach_z := settlement_cemetery_world_point(site, 0, -half_depth - 5)
    approach_y := terrain.sample_surface_height(&editor.project, 0, approach_x, approach_z)
    world_box_rotated(
        {approach_x, approach_y + .025, approach_z},
        {site.plan.path_width, .05, 10},
        site.rotation,
        path_color,
    )
    wall_height, thickness := f32(.62), f32(.30)
    front_segment_width := (site.plan.width - site.plan.gate_width) * .5
    front_segment_offset := (site.plan.gate_width + front_segment_width) * .5
    wall_specs := [5][4]f32 {
        {-half_width, 0, thickness, site.plan.depth},
        {half_width, 0, thickness, site.plan.depth},
        {0, half_depth, site.plan.width, thickness},
        {-front_segment_offset, -half_depth, front_segment_width, thickness},
        {front_segment_offset, -half_depth, front_segment_width, thickness},
    }
    for wall in wall_specs {
        along_x := wall[2] >= wall[3]
        length := along_x ? wall[2] : wall[3]
        segments := max(int(math.ceil(length / 2)), 1)
        segment_length := length / f32(segments)
        for segment in 0 ..< segments {
            along := -length * .5 + segment_length * (f32(segment) + .5)
            local_x := wall[0] + (along_x ? along : f32(0))
            local_z := wall[1] + (along_x ? f32(0) : along)
            x, z := settlement_cemetery_world_point(site, local_x, local_z)
            y := terrain.sample_surface_height(&editor.project, 0, x, z)
            size_x := along_x ? segment_length + .03 : wall[2]
            size_z := along_x ? wall[3] : segment_length + .03
            world_box_rotated({x, y + wall_height * .5, z}, {size_x, wall_height, size_z}, site.rotation, wall_color)
        }
    }

    for grave in site.plan.graves[:site.plan.grave_count] {
        world_grave := grave
        world_grave.x, world_grave.z = settlement_cemetery_world_point(site, grave.x, grave.z)
        world_grave.rotation += site.rotation
        world_grave.ground_y = terrain.sample_surface_height(&editor.project, 0, world_grave.x, world_grave.z)
        cemetery_lab_draw_grave(world_grave)
    }

    memorial := site.plan.memorial
    memorial.x, memorial.z = settlement_cemetery_world_point(site, memorial.x, memorial.z)
    memorial.rotation += site.rotation
    memorial_y := terrain.sample_surface_height(&editor.project, 0, memorial.x, memorial.z)
    cemetery_lab_draw_memorial(memorial, path_color, memorial_y)

    if !include_trees do return
    for tree, tree_index in site.plan.trees[:site.plan.tree_count] {
        x, z := settlement_cemetery_world_point(site, tree.x, tree.z)
        y := terrain.sample_surface_height(&editor.project, 0, x, z)
        species := tree_index % 4 == 1 ? plants.Species.Olive : .Italian_Cypress
        _ = world_generated_plant(
            species,
            u64(site.plan.seed) << 32 ~ u64(tree_index + 1),
            third_person.Vec3{x, y, z},
            species == .Olive ? f32(.72) : f32(.78),
            site.rotation + f32(tree_index) * .73,
            .Free_Standing,
            nil,
            .Medium,
            0,
            .86,
        )
    }
}

gameplay_physics_add_settlement_cemetery :: proc(editor: ^Editor) {
    if editor == nil || editor.gameplay_physics.world == nil do return
    site := settlement_cemetery_derive(editor)
    if !site.valid do return
    state := &editor.gameplay_physics
    half_width, half_depth := site.plan.width * .5, site.plan.depth * .5
    front_width := (site.plan.width - site.plan.gate_width) * .5
    front_offset := (site.plan.gate_width + front_width) * .5
    walls := [5][4]f32 {
        {-half_width, 0, .30, site.plan.depth},
        {half_width, 0, .30, site.plan.depth},
        {0, half_depth, site.plan.width, .30},
        {-front_offset, -half_depth, front_width, .30},
        {front_offset, -half_depth, front_width, .30},
    }
    for wall, wall_index in walls {
        along_x := wall[2] >= wall[3]
        length := along_x ? wall[2] : wall[3]
        segments := max(int(math.ceil(length / 2)), 1)
        segment_length := length / f32(segments)
        for segment in 0 ..< segments {
            along := -length * .5 + segment_length * (f32(segment) + .5)
            local_x := wall[0] + (along_x ? along : f32(0))
            local_z := wall[1] + (along_x ? f32(0) : along)
            x, z := settlement_cemetery_world_point(site, local_x, local_z)
            y := terrain.sample_surface_height(&editor.project, 0, x, z)
            half_x := along_x ? segment_length * .5 + .015 : wall[2] * .5
            half_z := along_x ? wall[3] * .5 : segment_length * .5 + .015
            body := gameplay_physics_add_static_box(
                state,
                {half_x, .31, half_z},
                {x, y + .31, z},
                site.rotation,
                u64(0x2c00_0000) | (u64(wall_index) << 8) | u64(segment),
            )
            if body != physics.INVALID_BODY do append(&state.static_bodies, body)
        }
    }
    for grave, grave_index in site.plan.graves[:site.plan.grave_count] {
        x, z := settlement_cemetery_world_point(site, grave.x, grave.z)
        y := terrain.sample_surface_height(&editor.project, 0, x, z)
        body := gameplay_physics_add_static_box(
            state,
            {grave.width * .5, max(grave.height * .5, f32(.10)), grave.depth * .5},
            {x, y + max(grave.height * .5, f32(.10)), z},
            grave.rotation + site.rotation,
            u64(0x2d00_0000) | u64(grave_index),
        )
        if body != physics.INVALID_BODY do append(&state.static_bodies, body)
    }
    memorial := site.plan.memorial
    x, z := settlement_cemetery_world_point(site, memorial.x, memorial.z)
    y := terrain.sample_surface_height(&editor.project, 0, x, z)
    body := gameplay_physics_add_static_box(
        state,
        {memorial.base_width * .5, memorial.height * .5, memorial.base_width * .42},
        {x, y + memorial.height * .5, z},
        memorial.rotation + site.rotation,
        u64(0x2e00_0000),
    )
    if body != physics.INVALID_BODY do append(&state.static_bodies, body)
}
