package main

import harbor "../packages/harbor"
import terrain "../packages/terrain"

marine_habitat_append_plan_exclusions :: proc(
    exclusions: ^[dynamic]terrain.Marine_Habitat_Exclusion,
    plan: ^harbor.Harbor_Plan,
) {
    if exclusions == nil || plan == nil || !plan.valid do return
    for point in plan.navigable_water.points[:plan.navigable_water.count] {
        append(exclusions, terrain.Marine_Habitat_Exclusion{center_x = point.x, center_z = point.z, radius = 18})
    }
    for point in plan.fairway.points[:plan.fairway.count] {
        append(exclusions, terrain.Marine_Habitat_Exclusion{center_x = point.x, center_z = point.z, radius = 14})
    }
    for edit in plan.terrain_edits[:plan.terrain_edit_count] {
        append(
            exclusions,
            terrain.Marine_Habitat_Exclusion {
                center_x = edit.center.x,
                center_z = edit.center.z,
                radius = edit.radius + 4,
            },
        )
    }
}

marine_habitat_rebuild_world :: proc(editor: ^Editor) {
    if editor == nil do return
    exclusions := make([dynamic]terrain.Marine_Habitat_Exclusion, 0, 256)
    defer delete(exclusions)
    for index in 0 ..< editor.default_marina_count {
        marine_habitat_append_plan_exclusions(&exclusions, &editor.default_harbors[index])
    }
    if editor.marina_authored {
        marine_habitat_append_plan_exclusions(&exclusions, &editor.harbor_authored_plan)
    }
    terrain.marine_habitat_rebuild_all(&editor.project, exclusions[:])
}
