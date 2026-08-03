// Package plant_structure defines renderer-independent plant geometry.
//
// It intentionally contains no grammar or species policy. Botanical generators
// produce this representation and renderers may mesh, cluster, or billboard it.
package plant_structure

Vec3 :: [3]f32

Segment :: struct {
    start:        Vec3,
    end:          Vec3,
    radius_start: f32,
    radius_end:   f32,
    depth:        int,
}

Attachment_Anchor :: struct {
    position: Vec3,
    forward:  Vec3,
    up:       Vec3,
    depth:    int,
}

Leaf :: Attachment_Anchor

// Plant is the sole renderer-neutral snapshot exchanged between botanical
// architecture generation, pruning, meshing, and presentation.
Plant :: struct {
    segments: [dynamic]Segment,
    leaves:   [dynamic]Attachment_Anchor,
}

destroy_plant :: proc(plant: ^Plant) {
    if plant == nil do return
    delete(plant.segments)
    delete(plant.leaves)
    plant^ = {}
}

Interpret_Error :: enum {
    None,
    Invalid_Geometry,
}

Interpret_Result :: struct {
    plant: Plant,
    error: Interpret_Error,
}

// SplitMix64 is shared by architecture families so a seed has one stable,
// deterministic interpretation across the complete catalog.
random_next :: proc(state: ^u64) -> u64 {
    state^ += 0x9e3779b97f4a7c15
    z := state^
    z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ~ (z >> 27)) * 0x94d049bb133111eb
    return z ~ (z >> 31)
}

Bounds :: struct {
    minimum: Vec3,
    maximum: Vec3,
}
