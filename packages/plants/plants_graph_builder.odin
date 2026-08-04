package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

Graph_Builder :: struct {
    graph:    Plant_Graph,
    seed:     u64,
    maturity: f32,
    profile:  Garden_Profile,
}

graph_builder_make :: proc(species: Species, seed: u64, maturity: f32) -> Graph_Builder {
    return {seed = seed, maturity = clamp(maturity, f32(0), f32(1)), profile = garden_profile(species)}
}

graph_builder_destroy :: proc(builder: ^Graph_Builder) {
    if builder == nil do return
    destroy_graph(&builder.graph)
    builder^ = {}
}

graph_builder_take :: proc(builder: ^Graph_Builder) -> Plant_Graph {
    if builder == nil do return {}
    graph := builder.graph
    builder.graph = {}
    return graph
}

graph_builder_id :: #force_inline proc(builder: ^Graph_Builder, domain, stable_key: u64) -> u64 {
    return generated_stable_id(builder.seed ~ stable_key * 0x9e3779b97f4a7c15, domain, int(stable_key & 0x7fffffff))
}

graph_builder_growth :: #force_inline proc(builder: ^Graph_Builder, emergence, duration: f32) -> (f32, bool) {
    if builder == nil || builder.maturity < emergence do return 0, false
    progress := clamp((builder.maturity - emergence) / max(duration, f32(.0001)), f32(0), f32(1))
    return progress * progress * (3 - 2 * progress), true
}

graph_builder_axis :: proc(
    builder: ^Graph_Builder,
    parent_axis, parent_internode: int,
    role: Axis_Role,
    orientation: Axis_Orientation,
    stable_key: u64,
    emergence: f32 = 0,
    vigor: f32 = 1,
) -> (
    axis, growth_unit: int,
    visible: bool,
) {
    progress, is_visible := graph_builder_growth(builder, emergence, .18)
    if !is_visible do return -1, -1, false
    order := u8(0)
    if parent_axis >= 0 do order = builder.graph.axes[parent_axis].order + 1
    axis = graph_add_axis(
        &builder.graph,
        parent_axis,
        parent_internode,
        role,
        orientation,
        order,
        clamp(vigor, f32(.01), f32(1)),
        builder.maturity,
    )
    builder.graph.axes[axis].stable_id = graph_builder_id(builder, 0x41584953, stable_key)
    builder.graph.axes[axis].active = progress < 1 || builder.maturity < 1
    phase := builder.profile.phyllotactic_angle * f32(stable_key & 0xffff)
    growth_unit = graph_begin_growth_unit(&builder.graph, axis, phase, progress)
    builder.graph.growth_units[growth_unit].stable_id = graph_builder_id(builder, 0x47524f575448, stable_key)
    return axis, growth_unit, true
}

graph_builder_internode :: proc(
    builder: ^Graph_Builder,
    axis, growth_unit, parent: int,
    start, full_end: plant_structure.Vec3,
    radius_start, radius_end: f32,
    stable_key: u64,
    emergence: f32 = 0,
) -> int {
    progress, visible := graph_builder_growth(builder, emergence, .14)
    if !visible || axis < 0 || growth_unit < 0 do return -1
    end := start + (full_end - start) * max(progress, f32(.02))
    radius_scale := max(f32(math.sqrt(f64(max(progress, f32(.01))))), f32(.1))
    internode := graph_add_internode(
        &builder.graph,
        axis,
        growth_unit,
        parent,
        start,
        end,
        max(radius_start * radius_scale, f32(.0005)),
        max(radius_end * radius_scale, f32(.00025)),
        builder.maturity,
        int(builder.graph.axes[axis].order),
    )
    builder.graph.internodes[internode].stable_id = graph_builder_id(builder, 0x494e544552, stable_key)
    return internode
}

graph_builder_organ :: proc(
    builder: ^Graph_Builder,
    internode: int,
    fraction: f32,
    kind: Architecture_Organ,
    forward, up: plant_structure.Vec3,
    stable_key: u64,
    emergence: f32 = 0,
    variant: u8 = 0,
) -> int {
    _, visible := graph_builder_growth(builder, emergence, .08)
    if !visible || internode < 0 do return -1
    index := len(builder.graph.organs)
    graph_add_organ(
        &builder.graph,
        internode,
        fraction,
        kind,
        linalg.normalize0(forward),
        linalg.normalize0(up),
        variant,
        builder.graph.internodes[internode].render_depth,
    )
    builder.graph.organs[index].stable_id = graph_builder_id(builder, 0x4f5247414e, stable_key)
    return index
}

graph_builder_leader :: proc(
    builder: ^Graph_Builder,
    points: []plant_structure.Vec3,
    base_radius, tip_radius: f32,
    stable_key: u64,
    emergence: f32 = 0,
) -> int {
    if len(points) < 2 do return -1
    axis, unit, visible := graph_builder_axis(builder, -1, -1, .Leader, .Orthotropic, stable_key, emergence)
    if !visible do return -1
    parent := -1
    for point_index in 0 ..< len(points) - 1 {
        t0 := f32(point_index) / f32(len(points) - 1)
        t1 := f32(point_index + 1) / f32(len(points) - 1)
        parent = graph_builder_internode(
            builder,
            axis,
            unit,
            parent,
            points[point_index],
            points[point_index + 1],
            linalg.lerp(base_radius, tip_radius, t0),
            linalg.lerp(base_radius, tip_radius, t1),
            stable_key * 256 + u64(point_index),
            emergence + f32(point_index) * .025,
        )
    }
    if parent >= 0 {
        append(
            &builder.graph.buds,
            Bud {
                internode = parent,
                state = builder.maturity < 1 ? Bud_State.Continuing : .Terminated,
                vigor = 1,
                stable_id = graph_builder_id(builder, 0x425544, stable_key),
            },
        )
    }
    return axis
}

graph_builder_shoot :: proc(
    builder: ^Graph_Builder,
    parent_internode: int,
    direction: plant_structure.Vec3,
    length, radius: f32,
    role: Axis_Role,
    orientation: Axis_Orientation,
    stable_key: u64,
    emergence: f32,
) -> int {
    if parent_internode < 0 || parent_internode >= len(builder.graph.internodes) do return -1
    parent_node := builder.graph.internodes[parent_internode]
    axis, unit, visible := graph_builder_axis(
        builder,
        parent_node.axis,
        parent_internode,
        role,
        orientation,
        stable_key,
        emergence,
        builder.graph.axes[parent_node.axis].vigor * .78,
    )
    if !visible do return -1
    normalized_direction := linalg.normalize0(direction)
    internode := graph_builder_internode(
        builder,
        axis,
        unit,
        parent_internode,
        parent_node.end,
        parent_node.end + normalized_direction * length,
        radius,
        radius * .28,
        stable_key * 256,
        emergence,
    )
    if internode >= 0 {
        append(
            &builder.graph.buds,
            Bud {
                internode = internode,
                state = builder.maturity < 1 ? Bud_State.Continuing : .Terminated,
                vigor = builder.graph.axes[axis].vigor,
                stable_id = graph_builder_id(builder, 0x425544, stable_key),
            },
        )
    }
    return axis
}

graph_builder_lateral_shoot :: proc(
    builder: ^Graph_Builder,
    parent_internode: int,
    direction: plant_structure.Vec3,
    length, radius: f32,
    stable_key: u64,
    emergence: f32,
) -> int {
    return graph_builder_shoot(
        builder,
        parent_internode,
        direction,
        length,
        radius,
        .Lateral,
        .Plagiotropic,
        stable_key,
        emergence,
    )
}

graph_builder_renewal_cane :: proc(
    builder: ^Graph_Builder,
    parent_internode: int,
    direction: plant_structure.Vec3,
    length, radius: f32,
    stable_key: u64,
    emergence: f32,
) -> int {
    return graph_builder_shoot(
        builder,
        parent_internode,
        direction,
        length,
        radius,
        .Renewal_Cane,
        .Arching,
        stable_key,
        emergence,
    )
}

graph_builder_runner :: proc(
    builder: ^Graph_Builder,
    parent_internode: int,
    direction: plant_structure.Vec3,
    length, radius: f32,
    stable_key: u64,
    emergence: f32,
) -> int {
    return graph_builder_shoot(
        builder,
        parent_internode,
        direction,
        length,
        radius,
        .Runner,
        .Prostrate,
        stable_key,
        emergence,
    )
}

graph_builder_climber :: proc(
    builder: ^Graph_Builder,
    parent_internode: int,
    direction: plant_structure.Vec3,
    length, radius: f32,
    stable_key: u64,
    emergence: f32,
    twining: bool = false,
) -> int {
    orientation := twining ? Axis_Orientation.Twining : .Arching
    return graph_builder_shoot(
        builder,
        parent_internode,
        direction,
        length,
        radius,
        .Climber,
        orientation,
        stable_key,
        emergence,
    )
}

graph_builder_whorl :: proc(
    builder: ^Graph_Builder,
    parent_internode, count: int,
    elevation, length, radius: f32,
    stable_key: u64,
    emergence: f32,
) {
    for member in 0 ..< count {
        angle := f32(member) * math.TAU / f32(max(count, 1)) + f32(stable_key & 255) * .013
        direction := plant_structure.Vec3 {
            math.cos(angle) * math.cos(elevation),
            math.sin(elevation),
            math.sin(angle) * math.cos(elevation),
        }
        _ = graph_builder_lateral_shoot(
            builder,
            parent_internode,
            direction,
            length,
            radius,
            stable_key * 64 + u64(member),
            emergence,
        )
    }
}

graph_builder_bifurcation :: proc(
    builder: ^Graph_Builder,
    parent_internode: int,
    forward, side: plant_structure.Vec3,
    angle, length, radius: f32,
    stable_key: u64,
    emergence: f32,
) -> [2]int {
    normalized_forward := linalg.normalize0(forward)
    normalized_side := linalg.normalize0(side)
    return {
        graph_builder_lateral_shoot(
            builder,
            parent_internode,
            linalg.normalize0(normalized_forward * math.cos(angle) + normalized_side * math.sin(angle)),
            length,
            radius,
            stable_key * 2,
            emergence,
        ),
        graph_builder_lateral_shoot(
            builder,
            parent_internode,
            linalg.normalize0(normalized_forward * math.cos(angle) - normalized_side * math.sin(angle)),
            length,
            radius,
            stable_key * 2 + 1,
            emergence,
        ),
    }
}

graph_builder_rosette :: proc(
    builder: ^Graph_Builder,
    parent_internode, count: int,
    upward_bias: f32,
    stable_key: u64,
    emergence: f32,
) {
    for leaf in 0 ..< count {
        angle := f32(leaf) * builder.profile.phyllotactic_angle
        forward := linalg.normalize0(plant_structure.Vec3{math.cos(angle), upward_bias, math.sin(angle)})
        up := linalg.normalize0(
            plant_structure.Vec3{-math.cos(angle) * upward_bias, 1, -math.sin(angle) * upward_bias},
        )
        _ = graph_builder_organ(
            builder,
            parent_internode,
            .08,
            .Rosette_Leaf,
            forward,
            up,
            stable_key * 64 + u64(leaf),
            emergence + f32(leaf) * .006,
            u8(leaf & 3),
        )
    }
}

graph_builder_reproductive :: proc(
    builder: ^Graph_Builder,
    internode: int,
    fraction: f32,
    kind: Architecture_Organ,
    stable_key: u64,
    emergence: f32,
) -> int {
    return graph_builder_organ(builder, internode, fraction, kind, {0, 1, 0}, {1, 0, 0}, stable_key, emergence)
}
