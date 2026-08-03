package architecture
import buildings "../buildings"
import plants "../plants"
import terrain "../terrain"
import "core:math"
architecture_frontage_rotation :: proc(tangent_x, tangent_z, frontage_side: f32) -> f32 {
    rotation := f32(math.atan2(f64(tangent_z), f64(tangent_x)))
    if frontage_side > 0 do rotation += math.PI
    return rotation
}
@(no_instrumentation)
bougainvillea_maturity :: #force_inline proc(growth_density: f32) -> f32 {
    return plants.maturity_for_species(.Bougainvillea, growth_density)
}
@(no_instrumentation)
bougainvillea_palette :: #force_inline proc(seed: u32) -> int {
    mixed := city_hash(int(seed & 0x0000ffff), int(seed >> 16), seed ~ 0xa511e9b3)
    return int(mixed % 3)
}
@(no_instrumentation)
bougainvillea_training_habit :: #force_inline proc(seed: u32) -> int {
    mixed := city_hash(int(seed & 0x0000ffff), int(seed >> 16), seed ~ 0x6d2b79f5)
    return int(mixed % 2)
}
BOUGAINVILLEA_VALIDATION_SEEDS :: [6]u32{2, 15, 0, 4, 12, 8}
@(no_instrumentation)
bougainvillea_planter_rooted :: #force_inline proc(seed: u32) -> bool {
    return seed % 3 != 0
}
@(no_instrumentation)
bougainvillea_flower_tile_base :: #force_inline proc(palette: int) -> int {
    switch ((palette % 3) + 3) % 3 {
    case 0:
        return 8 // magenta
    case 1:
        return 4 // coral
    case 2:
        return 12 // violet
    }
    return 8
}
bougainvillea_bract_color :: proc(palette: int) -> [4]u8 {
    switch ((palette % 3) + 3) % 3 {
    case 0:
        return {213, 65, 132, 255} // magenta
    case 1:
        return {226, 100, 86, 255} // coral
    case 2:
        return {144, 65, 190, 255} // violet
    }
    return {213, 65, 132, 255}
}
@(no_instrumentation)
bougainvillea_bract_value :: #force_inline proc(maturity, node_fraction: f32, variation: int) -> f32 {
    age_gradient := clamp(node_fraction, 0, 1)
    maturity_lift := clamp(maturity, 0, 1) * .012
    variation_lift := f32(((variation % 4) + 4) % 4) * .009
    return clamp(.895 + age_gradient * .075 + maturity_lift + variation_lift, .895, 1.01)
}
@(no_instrumentation)
bougainvillea_active_branch_count :: #force_inline proc(maturity: f32, available_branches: int) -> int {
    if available_branches <= 0 do return 0
    return min(2 + int(clamp(maturity, 0, 1) * 4.0 + .5), available_branches)
}
bougainvillea_thorn_count :: proc(maturity: f32, available_nodes: int) -> int {
    if available_nodes <= 0 || maturity <= .38 do return 0
    return min(1 + int((clamp(maturity, 0, 1) - .38) * 5.0), available_nodes)
}
@(no_instrumentation)
bougainvillea_fallen_bract_count :: #force_inline proc(maturity: f32) -> int {
    if maturity <= .62 do return 0
    return min(2 + int((clamp(maturity, 0, 1) - .62) * 8.0), 5)
}
@(no_instrumentation)
bougainvillea_cascade_count :: #force_inline proc(maturity: f32) -> int {
    if maturity <= .56 do return 0
    return maturity < .84 ? 1 : 2
}
@(no_instrumentation)
bougainvillea_secondary_leader_strength :: #force_inline proc(maturity: f32) -> f32 {
    strength := clamp((maturity - .46) / .34, 0, 1)
    return strength * strength * (3 - 2 * strength)
}
bougainvillea_woody_compliance :: proc(maturity: f32) -> f32 {
    return plants.woody_wind_compliance(.Bougainvillea, maturity)
}
@(no_instrumentation)
bougainvillea_detail_tier :: #force_inline proc(camera_distance: f32) -> int {
    return plants.detail_tier(camera_distance)
}
@(no_instrumentation)
bougainvillea_crown_detail_fade :: #force_inline proc(camera_distance: f32) -> f32 {
    fade := clamp((112 - camera_distance) / 24, 0, 1)
    return fade * fade * (3 - 2 * fade)
}
@(no_instrumentation)
bougainvillea_branch_flowering :: #force_inline proc(
    maturity, node_fraction: f32,
    seed: u32,
    branch_index: int,
) -> bool {
    clamped_maturity := clamp(maturity, 0, 1)
    bloom_threshold := .82 - clamped_maturity * .26
    if clamped_maturity <= .16 || node_fraction <= bloom_threshold do return false
    if clamped_maturity > .82 {
        if branch_index == 5 do return true
        resting_branch := 1 + int(city_hash(int(seed & 0xffff), int(seed >> 16), seed ~ 0x91e10da5) % 4)
        if branch_index == resting_branch do return false
    }
    bloom_slots := 1 + int(clamped_maturity * 3.99)
    mixed := city_hash(branch_index, int(seed & 0xffff), seed ~ 0x4f1bbcdc)
    return int(mixed % 5) < bloom_slots
}
@(no_instrumentation)
bougainvillea_basal_shoot_count :: #force_inline proc(maturity: f32) -> int {
    if maturity <= .34 do return 0
    return maturity < .78 ? 1 : 2
}
bougainvillea_pruned_stub_count :: proc(maturity: f32) -> int {
    if maturity <= .52 do return 0
    return min(1 + int((clamp(maturity, 0, 1) - .52) * 5.0), 3)
}
@(no_instrumentation)
bougainvillea_root_attachment_x :: #force_inline proc(
    structure: terrain.Structure,
    preferred_x: f32,
    seed: u32,
) -> f32 {
    if structure.kind != .Architecture do return preferred_x
    side := preferred_x < 0 ? f32(-1) : f32(1)
    if math.abs(preferred_x) < .001 do side = seed & 1 == 0 ? f32(-1) : f32(1)
    minimum_offset := structure.width * .52
    resolved := side * max(math.abs(preferred_x), minimum_offset)
    return clamp(resolved, -structure.width * .58, structure.width * .58)
}
@(no_instrumentation)
bougainvillea_height_fraction :: #force_inline proc(maturity: f32) -> f32 {
    return .24 + clamp(maturity, 0, 1) * .60
}
bougainvillea_density_at_structure :: proc(
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    structure: terrain.Structure,
    project: ^terrain.Project = nil,
) -> f32 {
    if field == nil do return 0
    footprint := max(structure.width, structure.depth) * .42
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    density_sum: f32
    for sample in -2 ..= 2 {
        local_x := f32(sample) * footprint * .52
        local_z := f32((sample + int(structure.seed % 3)) % 3 - 1) * footprint * .16
        sample_x := structure.center_x + local_x * cosine - local_z * sine
        sample_z := structure.center_z + local_x * sine + local_z * cosine
        density_sum += city_density_sample(field, sample_x, sample_z, project)
    }
    return density_sum / 5
}
@(no_instrumentation)
bougainvillea_laundry_conflict :: #force_inline proc(
    structure: terrain.Structure,
    growth_density, line_world_y: f32,
) -> bool {
    if structure.kind != .Architecture || growth_density < .035 do return false
    maturity := bougainvillea_maturity(growth_density)
    if maturity <= .16 do return false
    branch_nodes := [6]int{7, 9, 11, 13, 14, 15}
    active_count := bougainvillea_active_branch_count(maturity, len(branch_nodes))
    lowest_node := branch_nodes[len(branch_nodes) - active_count]
    vine_height := structure.height * bougainvillea_height_fraction(maturity)
    crown_floor := structure.base_y + vine_height * f32(lowest_node) / 15 - .65
    crown_ceiling := structure.base_y + min(vine_height + 2.2, structure.height * .94)
    laundry_drop: f32 = 1.35
    return line_world_y >= crown_floor && line_world_y - laundry_drop <= crown_ceiling
}
@(no_instrumentation)
bougainvillea_laundry_span_conflict :: #force_inline proc(
    structure: terrain.Structure,
    growth_density, line_world_y, start_x, start_z, finish_x, finish_z: f32,
) -> bool {
    if !bougainvillea_laundry_conflict(structure, growth_density, line_world_y) do return false
    facade := architecture_frontage_structure(structure)
    span_x, span_z := finish_x - start_x, finish_z - start_z
    span_length_squared := span_x * span_x + span_z * span_z
    if span_length_squared <= .0001 do return false
    projection := clamp(
        ((facade.center_x - start_x) * span_x + (facade.center_z - start_z) * span_z) / span_length_squared,
        0,
        1,
    )
    closest_x := start_x + span_x * projection
    closest_z := start_z + span_z * projection
    offset_x, offset_z := facade.center_x - closest_x, facade.center_z - closest_z
    crown_radius := facade.depth * .5 + max(facade.width * .42, f32(2.4)) + .55
    return offset_x * offset_x + offset_z * offset_z <= crown_radius * crown_radius
}
