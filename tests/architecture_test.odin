package tests

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:testing"

@(test)
adriatic_graph_is_seed_stable_and_has_a_landmark :: proc(t: ^testing.T) {
    first := architecture.adriatic_graph(100, 200, 0xA71D3)
    second := architecture.adriatic_graph(100, 200, 0xA71D3)
    testing.expect(t, first.count == second.count)
    testing.expect(t, first.count >= 13)
    testing.expect(t, first.nodes[first.count - 1].kind == .Landmark)
    testing.expect(t, first.nodes[first.count - 1].z < 200)
    for index in 0 ..< first.count {
        testing.expect(t, first.nodes[index].x == second.nodes[index].x)
        testing.expect(t, first.nodes[index].height == second.nodes[index].height)
    }
}

@(test)
architecture_palette_keeps_landmark_distinct :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    architecture.generate(project, 1300, 1300, 0xA71D3)
    found_landmark := false
    found_variant := false
    for structure in project.structures[:project.structure_count] {
        if structure.height > 60 {
            found_landmark = structure.color == [4]u8{224, 219, 196, 255}
        } else if structure.color[0] != 214 {
            found_variant = true
        }
    }
    testing.expect(t, found_landmark)
    testing.expect(t, found_variant)
}

@(test)
architecture_palette_has_legible_seed_variants :: proc(t: ^testing.T) {
    first := architecture.architecture_color(0)
    second := architecture.architecture_color(1)
    third := architecture.architecture_color(2)
    fourth := architecture.architecture_color(3)
    testing.expect(t, first[0] != second[0] || first[1] != second[1])
    testing.expect(t, second[0] != third[0] || second[1] != third[1])
    testing.expect(t, third[0] != fourth[0] || third[1] != fourth[1])
    testing.expect(t, architecture.architecture_color(7)[0] == fourth[0])
}

@(test)
architecture_roof_palette_has_seed_variants :: proc(t: ^testing.T) {
    first := architecture.architecture_roof_color(0)
    second := architecture.architecture_roof_color(1)
    third := architecture.architecture_roof_color(2)
    fourth := architecture.architecture_roof_color(3)
    testing.expect(t, first != second)
    testing.expect(t, second != third)
    testing.expect(t, third != fourth)
    testing.expect(t, architecture.architecture_roof_color(8) == first)
    testing.expect(t, architecture.architecture_roof_color(8, true) == [4]u8{177, 92, 63, 255})
}

@(test)
architecture_roof_tiles_vary_by_seed_and_tone :: proc(t: ^testing.T) {
    testing.expect(t, architecture.architecture_roof_tile_color(0, 0) != architecture.architecture_roof_tile_color(1, 0))
    testing.expect(t, architecture.architecture_roof_tile_color(0, 0) != architecture.architecture_roof_tile_color(0, 1))
    testing.expect(t, architecture.architecture_roof_tile_color(8, 0) == architecture.architecture_roof_tile_color(0, 0))
    testing.expect(t, architecture.architecture_roof_tile_color(0, 7) == architecture.architecture_roof_tile_color(0, 2))
}

@(test)
architecture_generation_rejects_sea_level_sites :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    created := architecture.generate(project, 0, 0, 0xA71D3)
    testing.expect(t, created == 0)
    testing.expect(t, project.structure_count == 0)
}

@(test)
architecture_regeneration_preserves_seeded_styles :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    architecture.generate(project, 1300, 1300, 0xA71D3)
    first_seed := project.structures[0].seed
    first_color := project.structures[0].color
    architecture.generate(project, 1300, 1300, 0xA71D3)
    testing.expect(t, project.structures[0].seed == first_seed)
    testing.expect(t, project.structures[0].color == first_color)
}

@(test)
architecture_roof_styles_are_seed_stable :: proc(t: ^testing.T) {
    testing.expect(t, architecture.roof_style_for_seed(0) == .Gable)
    testing.expect(t, architecture.roof_style_for_seed(1) == .Low_Gable)
    testing.expect(t, architecture.roof_style_for_seed(2) == .Hip)
    testing.expect(t, architecture.roof_style_for_seed(3) == .Parapet)
    testing.expect(t, architecture.roof_style_for_seed(7) == architecture.roof_style_for_seed(3))
}

@(test)
architecture_facade_styles_are_decoupled_and_reproducible :: proc(t: ^testing.T) {
    variants: [4]bool
    for seed in 0 ..< 16 {
        style := architecture.facade_style_for_seed(u32(seed))
        testing.expect(t, style >= 0 && style < 4)
        testing.expect(t, style == architecture.facade_style_for_seed(u32(seed)))
        variants[style] = true
    }
    for variant in variants {
        testing.expect(t, variant)
    }
    testing.expect(t, architecture.facade_style_for_seed(0) != int(architecture.roof_style_for_seed(0)))
}

@(test)
architecture_chimney_variation_is_sparse_and_seed_stable :: proc(t: ^testing.T) {
    chimney_count := 0
    for seed in 0 ..< 12 {
        if architecture.architecture_has_chimney(u32(seed)) do chimney_count += 1
        testing.expect(t, architecture.architecture_has_chimney(u32(seed)) == (seed % 3 == 0))
    }
    testing.expect(t, chimney_count == 4)
}

@(test)
architecture_facade_floor_count_tracks_height :: proc(t: ^testing.T) {
    testing.expect(t, architecture.facade_floor_count(18) == 2)
    testing.expect(t, architecture.facade_floor_count(33) == 3)
    testing.expect(t, architecture.facade_floor_count(50) == 4)
    testing.expect(t, architecture.facade_floor_count(80) == 4)
}

@(test)
adriatic_graph_keeps_same_row_frontages_separated :: proc(t: ^testing.T) {
    graph := architecture.adriatic_graph(100, 200, 0xA71D3)
    for left_index in 0 ..< graph.count {
        left := graph.nodes[left_index]
        if left.kind != .Street_Block do continue
        for right_index in left_index + 1 ..< graph.count {
            right := graph.nodes[right_index]
            if right.kind != .Street_Block do continue
            if math.abs(left.z - right.z) > 12 do continue
            clearance := math.abs(left.x - right.x) - (left.width + right.width) * .5
            testing.expect(t, clearance >= -1)
        }
    }
}

@(test)
adriatic_graph_builds_a_rear_row_skyline :: proc(t: ^testing.T) {
    graph := architecture.adriatic_graph(100, 200, 0xA71D3)
    front_total, rear_total: f32
    front_count, rear_count := 0, 0
    for node in graph.nodes[:graph.count] {
        if node.kind != .Street_Block do continue
        if node.z < 180 {
            front_total += node.height
            front_count += 1
        } else if node.z > 220 {
            rear_total += node.height
            rear_count += 1
        }
    }
    testing.expect(t, front_count > 0 && rear_count > 0)
    testing.expect(t, rear_total / f32(rear_count) > front_total / f32(front_count) + 1)
}
