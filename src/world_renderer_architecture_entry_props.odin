package main
import "core:math"

import plants "../packages/plants"
import terrain "../packages/terrain"
import canvas2d "zelda_engine:canvas2d"

world_architecture_door_mat :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    door_width, door_height, door_center_local_y: f32,
    color: canvas2d.Color,
    accent: bool = false,
) {
    threshold_y := structure.base_y + door_center_local_y - door_height * .5
    wall_x, wall_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        structure.depth * .5,
        structure.rotation,
    )
    outward_x, outward_z := world_rotate_xz(0, 0, 0, 1, structure.rotation)
    tangent_x, tangent_z := world_rotate_xz(0, 0, 1, 0, structure.rotation)
    layout_choice := settlement_stoop_layout_choice(
        project,
        structure,
        {wall_x, wall_z},
        {outward_x, outward_z},
        {tangent_x, tangent_z},
        door_width,
        threshold_y,
        int(structure.seed % 3),
    )
    turned := layout_choice != 0
    turn_sign := layout_choice == 1 ? f32(-1) : f32(1)
    probe_local_x := f32(0)
    probe_local_z := structure.depth * .5 + (turned ? f32(.90) : f32(.72))
    if turned do probe_local_x = turn_sign * (door_width * .5 + 2.4)
    probe_x, probe_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        probe_local_x,
        probe_local_z,
        structure.rotation,
    )
    elevated := project != nil && threshold_y - terrain.sample_surface_height(project, 0, probe_x, probe_z) > .30
    // A straight flight has no level surface on which a loose mat can sit.
    // Turned stoops retain theirs on the landing; level entrances retain the
    // ordinary ground-level mat.
    if elevated && !turned do return

    mat_local_z := structure.depth * .5 + (elevated ? (turned ? f32(.42) : f32(.20)) : f32(1.02))
    mat_depth := elevated ? (turned ? f32(.56) : f32(.32)) : f32(.48)
    mat_y := elevated ? threshold_y + .025 : structure.base_y + .075
    mat_x, mat_z := world_rotate_xz(structure.center_x, structure.center_z, 0, mat_local_z, structure.rotation)
    world_box_rotated({mat_x, mat_y, mat_z}, {door_width * .78, .04, mat_depth}, structure.rotation, color)
    if accent {
        edge_x, edge_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            mat_local_z + mat_depth * .5 + .025,
            structure.rotation,
        )
        world_box_rotated(
            {edge_x, mat_y + .017, edge_z},
            {door_width * .82, .035, .055},
            structure.rotation,
            {184, 145, 77, 255},
        )
    }
}

world_architecture_residence_planter :: proc(
    project: ^terrain.Project,
    x, z, rotation: f32,
    seed: u32,
    side: int,
    pot_height: f32 = .46,
    cache_geometry: bool = false,
) {
    if project == nil do return
    ground_y := terrain.sample_surface_height(project, 0, x, z)
    pot_width: f32 = .44
    terracotta := side < 0 ? canvas2d.Color{169, 96, 61, 255} : canvas2d.Color{181, 105, 65, 255}
    world_box_rotated(
        {x, ground_y + pot_height * .5, z},
        {pot_width, pot_height, pot_width},
        rotation + math.PI * .25,
        terracotta,
    )
    world_box_rotated(
        {x, ground_y + pot_height - .035, z},
        {pot_width + .08, .10, pot_width + .08},
        rotation + math.PI * .25,
        formation_face_color(terracotta, math.PI, 0),
    )
    world_box_rotated(
        {x, ground_y + pot_height + .022, z},
        {pot_width - .08, .045, pot_width - .08},
        rotation + math.PI * .25,
        {75, 58, 42, 255},
    )

    // Reuse a bounded set of botanical architectures across residences while
    // retaining per-pot scale, orientation, and flowering variation.
    plant_seed := u64(seed & 31) ~ u64(side + 1) << 8 ~ 0x5245535f504f54
    pot_species := seed & 3 == 0 ? plants.Species.Agapanthus : .Pelargonium
    _ = world_generated_plant(
        pot_species,
        plant_seed,
        {x, ground_y + pot_height + .045, z},
        .42 + f32((seed >> 9) & 3) * .035,
        rotation + f32(side) * .38,
        maturity = .86,
        cache_geometry = cache_geometry,
    )
}
