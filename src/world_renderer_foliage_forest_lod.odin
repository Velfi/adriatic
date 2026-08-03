package main
import "core:math"

import terrain "../packages/terrain"

world_foliage_tree_hash :: #force_inline proc(value: u32) -> u32 {
    hash := value
    hash ~= hash >> 16
    hash *= 0x7feb352d
    hash ~= hash >> 15
    hash *= 0x846ca68b
    hash ~= hash >> 16
    return hash
}

world_foliage_forest_tree_local :: #force_inline proc(
    structure: terrain.Structure,
    tree_index: int,
) -> (
    local_x, local_z: f32,
) {
    // Each index owns one stable position, independent of the number of trees
    // emitted by the active LOD. Earlier radial placement divided by the
    // current tree count, so every crown slid across the grove whenever the
    // count changed. A two-dimensional low-discrepancy sequence spreads every
    // prefix across the full ellipse, while seed hashes only rotate/shift that
    // sequence per grove. Correlated offsets then gather neighboring indices
    // into loose copses without making their positions LOD-dependent.
    index := f32(tree_index)
    seed := f32(structure.seed)
    angle_phase_hash := world_foliage_tree_hash(structure.seed ~ u32(0x9e3779b9))
    radius_phase_hash := world_foliage_tree_hash(structure.seed ~ u32(0x68bc21eb))
    angle_phase := f64(angle_phase_hash & 0x00ffffff) / f64(0x01000000)
    radius_phase := f64(radius_phase_hash & 0x00ffffff) / f64(0x01000000)
    angle_value := f64(tree_index) * .7548776662466927 + angle_phase
    radius_value := f64(tree_index) * .5698402909980532 + radius_phase
    angle_unit := f32(angle_value - math.floor(angle_value))
    radius_unit := f32(radius_value - math.floor(radius_value))
    angle := angle_unit * math.TAU
    radial := .055 + .40 * f32(math.sqrt(f64(radius_unit))) + f32(math.sin(f64(seed * .011 + index * 1.91))) * .024
    radial = clamp(radial, .04, .47)
    group_x := f32(math.sin(f64(seed * .006 + index * .47))) * structure.width * .032
    group_z := f32(math.sin(f64(seed * .008 + index * .43 + 1.9))) * structure.depth * .032
    local_x = math.cos(angle) * structure.width * radial + group_x
    local_z = math.sin(angle) * structure.depth * radial + group_z
    return
}

world_foliage_is_forest :: #force_inline proc(
    width, depth, height: f32,
    lod: Structure_LOD,
    aerial_view: bool,
) -> (
    mature, woodland: bool,
) {
    wide, narrow := max(width, depth), min(width, depth)
    aspect := wide / max(narrow, f32(.01))
    mature = aspect < 1.8 && wide >= 105 && height >= 58
    // A broad young grove joins the woodland only after its individual plants
    // cease to read clearly. Ground-level Near rendering remains a shrub mass.
    woodland = mature || ((lod != .Near || aerial_view) && aspect < 1.8 && wide >= 82 && height >= 40)
    return
}

world_foliage_far_forest_mass :: proc(structure: terrain.Structure, width, depth, canopy_lift: f32) {
    // Seven decimated crowns alone read as separate gumdrops. Lay three broad,
    // low shelves underneath them so the distant value shape becomes one
    // hand-painted woodland mass; the retained crowns provide the scalloped
    // edge and emergent hierarchy. The overlap is intentionally generous and
    // remains below the crown tops, avoiding a single inflated ellipsoid.
    offsets := [3][2]f32{{-.13, -.04}, {.14, .055}, {.015, -.12}}
    scales := [3][2]f32{{.69, .74}, {.66, .70}, {.57, .61}}
    heights := [3]f32{.105, .115, .092}
    for offset, index in offsets {
        mass := structure
        mass.seed += u32(0x517cc1b7 + index * 977)
        local_x := width * offset[0]
        local_z := depth * offset[1]
        world_foliage_lobe(
            mass,
            local_x,
            local_z,
            width * scales[index][0],
            depth * scales[index][1],
            structure.height * heights[index],
            canopy_lift * (.78 + f32(index) * .045),
            false,
            40 + index,
            math.atan2(local_z / max(depth, f32(.01)), local_x / max(width, f32(.01))),
            false,
            .Far,
            structure.rotation + f32(index) * .71,
        )
    }
}

world_foliage_far_forest_should_bridge :: #force_inline proc(
    a, b: terrain.Structure,
) -> (
    bridge: bool,
    distance, radius_a, radius_b: f32,
) {
    if a.kind != .Foliage || b.kind != .Foliage || a.id == b.id do return
    _, a_is_forest := world_foliage_is_forest(a.width, a.depth, a.height, .Far, true)
    _, b_is_forest := world_foliage_is_forest(b.width, b.depth, b.height, .Far, true)
    if !a_is_forest || !b_is_forest do return
    dx, dz := b.center_x - a.center_x, b.center_z - a.center_z
    distance = f32(math.sqrt(f64(dx * dx + dz * dz)))
    radius_a = f32(math.sqrt(f64(a.width * a.depth))) * .5
    radius_b = f32(math.sqrt(f64(b.width * b.depth))) * .5
    // Slightly separated painted groves still belong to one distant value
    // shape. Keep the permitted gap proportional to crown scale and bounded
    // so unrelated woods across a clearing never acquire a bridge.
    permitted_gap := clamp(min(radius_a, radius_b) * .34, f32(10), f32(22))
    bridge = distance <= radius_a + radius_b + permitted_gap
    return
}

world_foliage_far_forest_bridges :: proc(structure: terrain.Structure) {
    if world_renderer.editor == nil do return
    for neighbor in world_renderer.editor.project.structures[:world_renderer.editor.project.structure_count] {
        // Stable ID ownership emits every undirected pair exactly once even
        // when visibility ordering changes with the camera.
        if neighbor.id <= structure.id do continue
        bridge, distance, radius_a, radius_b := world_foliage_far_forest_should_bridge(structure, neighbor)
        if !bridge || distance <= .001 do continue

        dx, dz := neighbor.center_x - structure.center_x, neighbor.center_z - structure.center_z
        angle := math.atan2(dz, dx)
        midpoint_x := (structure.center_x + neighbor.center_x) * .5
        midpoint_z := (structure.center_z + neighbor.center_z) * .5
        smaller_radius := min(radius_a, radius_b)
        bridge_structure := structure
        bridge_structure.center_x = midpoint_x
        bridge_structure.center_z = midpoint_z
        bridge_structure.base_y = terrain.sample_surface_height(&world_renderer.editor.project, 0, midpoint_x, midpoint_z)
        bridge_structure.rotation = angle
        bridge_structure.seed = world_foliage_tree_hash(structure.seed ~ neighbor.seed ~ u32(0x6d2b79f5))
        bridge_structure.width = distance + smaller_radius * .72
        bridge_structure.depth = smaller_radius * 1.18
        bridge_structure.height = min(structure.height, neighbor.height)
        world_foliage_lobe(
            bridge_structure,
            0,
            0,
            bridge_structure.width,
            bridge_structure.depth,
            bridge_structure.height * .095,
            bridge_structure.height * .085,
            false,
            73,
            angle,
            false,
            .Far,
            angle,
        )
    }
}

world_foliage_uses_cluster_mass :: #force_inline proc(lod: Structure_LOD, aerial_view: bool) -> bool {
    return lod == .Far || (lod == .Medium && aerial_view)
}
