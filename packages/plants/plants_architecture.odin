package plants

import plant_structure "../plant_structure"

Axis_Role :: enum u8 {
    Leader,
    Scaffold,
    Lateral,
    Renewal_Cane,
    Runner,
    Climber,
    Flowering_Shoot,
    Inflorescence,
}

Axis_Orientation :: enum u8 {
    Orthotropic,
    Plagiotropic,
    Mixed,
    Twining,
    Arching,
    Prostrate,
}

Bud_State :: enum u8 {
    Continuing,
    Lateral,
    Dormant,
    Terminated,
}

Architecture_Organ :: enum u8 {
    Leaf,
    Flower,
    Fruit,
    Thorn,
    Tendril,
    Cladode,
    Rosette_Leaf,
    Cactus_Rib,
}

Axis :: struct {
    parent_axis:      int,
    parent_internode: int,
    role:             Axis_Role,
    orientation:      Axis_Orientation,
    order:            u8,
    vigor:            f32,
    age:              f32,
    active:           bool,
    stable_id:        u64,
}

Growth_Unit :: struct {
    axis:               int,
    first_internode:    int,
    internode_count:    int,
    phyllotactic_phase: f32,
    progress:           f32,
    stable_id:          u64,
}

Internode :: struct {
    axis:         int,
    growth_unit:  int,
    parent:       int,
    start:        plant_structure.Vec3,
    end:          plant_structure.Vec3,
    radius_start: f32,
    radius_end:   f32,
    age:          f32,
    render_depth: int,
    stable_id:    u64,
}

Bud :: struct {
    internode: int,
    state:     Bud_State,
    vigor:     f32,
    stable_id: u64,
}

Organ_Site :: struct {
    internode:    int,
    fraction:     f32,
    kind:         Architecture_Organ,
    forward:      plant_structure.Vec3,
    up:           plant_structure.Vec3,
    variant:      u8,
    render_depth: int,
    stable_id:    u64,
}

Plant_Graph :: struct {
    axes:         [dynamic]Axis,
    growth_units: [dynamic]Growth_Unit,
    internodes:   [dynamic]Internode,
    buds:         [dynamic]Bud,
    organs:       [dynamic]Organ_Site,
}

destroy_graph :: proc(graph: ^Plant_Graph) {
    if graph == nil do return
    delete(graph.axes)
    delete(graph.growth_units)
    delete(graph.internodes)
    delete(graph.buds)
    delete(graph.organs)
    graph^ = {}
}

graph_add_axis :: proc(
    graph: ^Plant_Graph,
    parent_axis, parent_internode: int,
    role: Axis_Role,
    orientation: Axis_Orientation,
    order: u8,
    vigor, age: f32,
) -> int {
    index := len(graph.axes)
    append(&graph.axes, Axis{parent_axis, parent_internode, role, orientation, order, vigor, age, true, 0})
    return index
}

graph_begin_growth_unit :: proc(graph: ^Plant_Graph, axis: int, phase, progress: f32) -> int {
    index := len(graph.growth_units)
    append(&graph.growth_units, Growth_Unit{axis, len(graph.internodes), 0, phase, progress, 0})
    return index
}

graph_add_internode :: proc(
    graph: ^Plant_Graph,
    axis, growth_unit, parent: int,
    start, end: plant_structure.Vec3,
    radius_start, radius_end, age: f32,
    render_depth: int = 0,
) -> int {
    index := len(graph.internodes)
    append(
        &graph.internodes,
        Internode{axis, growth_unit, parent, start, end, radius_start, radius_end, age, render_depth, 0},
    )
    graph.growth_units[growth_unit].internode_count += 1
    return index
}

graph_add_organ :: proc(
    graph: ^Plant_Graph,
    internode: int,
    fraction: f32,
    kind: Architecture_Organ,
    forward, up: plant_structure.Vec3,
    variant: u8 = 0,
    render_depth: int = 0,
) {
    append(&graph.organs, Organ_Site{internode, fraction, kind, forward, up, variant, render_depth, 0})
}
