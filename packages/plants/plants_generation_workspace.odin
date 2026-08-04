package plants

import plant_structure "../plant_structure"

Generation_Workspace :: struct {
    graph:             Plant_Graph,
    segments:          [dynamic]plant_structure.Segment,
    segment_parents:   [dynamic]int,
    segment_axes:      [dynamic]int,
    segment_ids:       [dynamic]u64,
    axis_parents:      [dynamic]int,
    axis_roles:        [dynamic]Axis_Role,
    axis_orientations: [dynamic]Axis_Orientation,
    attachments:       [dynamic]Attachment,
    attachment_ids:    [dynamic]u64,
    active:            bool,
    borrowed:          bool,
}

@(thread_local)
generation_active_workspace: ^Generation_Workspace

generation_workspace_begin :: proc(workspace: ^Generation_Workspace) -> bool {
    if workspace == nil do return true
    if workspace.active || workspace.borrowed || generation_active_workspace != nil do return false
    workspace.active = true
    generation_active_workspace = workspace
    return true
}

generation_workspace_end :: proc(workspace: ^Generation_Workspace) {
    if workspace == nil do return
    workspace.active = false
    if generation_active_workspace == workspace do generation_active_workspace = nil
}

generation_workspace_graph_take :: proc() -> Plant_Graph {
    workspace := generation_active_workspace
    if workspace == nil do return {}
    graph := workspace.graph
    workspace.graph = {}
    clear(&graph.axes)
    clear(&graph.growth_units)
    clear(&graph.internodes)
    clear(&graph.buds)
    clear(&graph.organs)
    return graph
}

generation_workspace_output_take :: proc(plant: ^Generated_Plant) {
    workspace := generation_active_workspace
    if workspace == nil || plant == nil do return
    plant.segments = workspace.segments
    plant.segment_parents = workspace.segment_parents
    plant.segment_axes = workspace.segment_axes
    plant.segment_ids = workspace.segment_ids
    plant.axis_parents = workspace.axis_parents
    plant.axis_roles = workspace.axis_roles
    plant.axis_orientations = workspace.axis_orientations
    plant.attachments = workspace.attachments
    plant.attachment_ids = workspace.attachment_ids
    clear(&plant.segments)
    clear(&plant.segment_parents)
    clear(&plant.segment_axes)
    clear(&plant.segment_ids)
    clear(&plant.axis_parents)
    clear(&plant.axis_roles)
    clear(&plant.axis_orientations)
    clear(&plant.attachments)
    clear(&plant.attachment_ids)
    workspace.segments = nil
    workspace.segment_parents = nil
    workspace.segment_axes = nil
    workspace.segment_ids = nil
    workspace.axis_parents = nil
    workspace.axis_roles = nil
    workspace.axis_orientations = nil
    workspace.attachments = nil
    workspace.attachment_ids = nil
}

generation_workspace_recycle_unadopted_graph :: proc(workspace: ^Generation_Workspace, graph: ^Plant_Graph) {
    if workspace == nil || graph == nil || len(workspace.graph.axes) > 0 do return
    workspace.graph = graph^
    graph^ = {}
}

generation_workspace_commit :: proc(workspace: ^Generation_Workspace, plant: ^Generated_Plant) {
    if workspace == nil || plant == nil do return
    workspace.borrowed = true
    plant.generation_workspace = workspace
}

generation_workspace_recycle_result :: proc(plant: ^Generated_Plant) -> bool {
    if plant == nil || plant.generation_workspace == nil do return false
    workspace := plant.generation_workspace
    if !workspace.borrowed do return false
    workspace.graph = plant.graph
    workspace.segments = plant.segments
    workspace.segment_parents = plant.segment_parents
    workspace.segment_axes = plant.segment_axes
    workspace.segment_ids = plant.segment_ids
    workspace.axis_parents = plant.axis_parents
    workspace.axis_roles = plant.axis_roles
    workspace.axis_orientations = plant.axis_orientations
    workspace.attachments = plant.attachments
    workspace.attachment_ids = plant.attachment_ids
    plant.graph = {}
    plant.segments = nil
    plant.segment_parents = nil
    plant.segment_axes = nil
    plant.segment_ids = nil
    plant.axis_parents = nil
    plant.axis_roles = nil
    plant.axis_orientations = nil
    plant.attachments = nil
    plant.attachment_ids = nil
    plant.generation_workspace = nil
    workspace.borrowed = false
    return true
}

generation_workspace_destroy :: proc(workspace: ^Generation_Workspace) {
    if workspace == nil do return
    destroy_graph(&workspace.graph)
    delete(workspace.segments)
    delete(workspace.segment_parents)
    delete(workspace.segment_axes)
    delete(workspace.segment_ids)
    delete(workspace.axis_parents)
    delete(workspace.axis_roles)
    delete(workspace.axis_orientations)
    delete(workspace.attachments)
    delete(workspace.attachment_ids)
    workspace^ = {}
}
