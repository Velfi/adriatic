package tests

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:testing"

@(test)
architecture_clusters_do_not_generate_a_parallel_road_network :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    centers := [2]f32{-1200, 1200}
    for center in centers {
        for index in 0 ..< 4 {
            structure := terrain.structure_make(
                center + f32(index % 2) * 28,
                center + f32(index / 2) * 28,
                12,
                10,
                0,
                18,
            )
            structure.kind = .Architecture
            _ = terrain.add_structure(project, structure)
        }
    }

    plan := architecture.circulation_plan(project)
    testing.expect_value(t, plan.count, 0)
}
