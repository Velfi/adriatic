package tests

import architecture "../packages/architecture"
import circulation "../packages/circulation"
import terrain "../packages/terrain"
import "core:testing"

@(test)
circulation_plan_keeps_distant_towns_independent :: proc(t: ^testing.T) {
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
    plaza_count := 0
    for area in plan.areas[:plan.count] {
        if area.kind == circulation.Area_Kind.Plaza do plaza_count += 1
        testing.expect(t, max(area.width, area.length) < 500)
    }
    testing.expect_value(t, plaza_count, 2)
}
