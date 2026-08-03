package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

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
}

Growth_Unit :: struct {
    axis:               int,
    first_internode:    int,
    internode_count:    int,
    phyllotactic_phase: f32,
    progress:           f32,
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
}

Bud :: struct {
    internode: int,
    state:     Bud_State,
    vigor:     f32,
}

Organ_Site :: struct {
    internode:    int,
    fraction:     f32,
    kind:         Architecture_Organ,
    forward:      plant_structure.Vec3,
    up:           plant_structure.Vec3,
    variant:      u8,
    render_depth: int,
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
    append(&graph.axes, Axis{parent_axis, parent_internode, role, orientation, order, vigor, age, true})
    return index
}

graph_begin_growth_unit :: proc(graph: ^Plant_Graph, axis: int, phase, progress: f32) -> int {
    index := len(graph.growth_units)
    append(&graph.growth_units, Growth_Unit{axis, len(graph.internodes), 0, phase, progress})
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
        Internode{axis, growth_unit, parent, start, end, radius_start, radius_end, age, render_depth},
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
    append(&graph.organs, Organ_Site{internode, fraction, kind, forward, up, variant, render_depth})
}

// graph_from_interpreted upgrades a renderer architecture into explicit botanical
// topology. It is the compatibility bridge used while family builders are
// migrated: after this point every downstream stage consumes graph-compiled
// output, never the source procedure's storage order or depth convention.
graph_from_interpreted :: proc(source: ^plant_structure.Plant, species: Species = .Olive, maturity: f32 = 1) -> Plant_Graph {
    graph: Plant_Graph
    if source == nil do return graph
    profile := garden_profile(species)
    segment_axes := make([]int, len(source.segments))
    defer delete(segment_axes)
    axis_units := make([dynamic]int)
    defer delete(axis_units)

    for segment, segment_index in source.segments {
        parent := -1
        for candidate_index := segment_index - 1; candidate_index >= 0; candidate_index -= 1 {
            delta := source.segments[candidate_index].end - segment.start
            if linalg.dot(delta, delta) <= 1e-8 {
                parent = candidate_index
                break
            }
        }
        axis := -1
        if parent >= 0 && source.segments[parent].depth == segment.depth {
            axis = segment_axes[parent]
        }
        if axis < 0 {
            parent_axis := parent >= 0 ? segment_axes[parent] : -1
            order := parent_axis >= 0 ? graph.axes[parent_axis].order + 1 : u8(0)
            role := order == 0 ? Axis_Role.Leader : order == 1 ? Axis_Role.Scaffold : Axis_Role.Lateral
            orientation_override := Axis_Orientation.Mixed
            #partial switch profile.family {
            case .Renewing_Shrub, .Subshrub:
                if order == 0 do role = .Renewal_Cane
            case .Tendril_Climber:
                role = .Climber
            case .Twining_Climber:
                role = .Climber
                orientation_override = .Twining
            case .Scrambling_Climber:
                role = .Climber
                orientation_override = .Arching
            case .Cushion:
                role = .Runner
                orientation_override = .Prostrate
            case .Rosette, .Stemmed_Succulent, .Cladode_Cactus, .Barrel_Cactus, .Columnar_Cactus:
            case .Reiterating_Tree, .Excurrent_Tree:
            }
            direction := linalg.normalize0(segment.end - segment.start)
            orientation := math.abs(direction[1]) > .72 ? Axis_Orientation.Orthotropic : Axis_Orientation.Plagiotropic
            if orientation_override != .Mixed do orientation = orientation_override
            vigor := clamp(1 - f32(order) * (profile.apical_control * .28), f32(.12), f32(1))
            axis = graph_add_axis(&graph, parent_axis, parent, role, orientation, order, vigor, maturity)
            phase := profile.phyllotactic_angle * f32(axis)
            append(&axis_units, graph_begin_growth_unit(&graph, axis, phase, maturity))
        }
        segment_axes[segment_index] = axis
        graph_add_internode(
            &graph,
            axis,
            axis_units[axis],
            parent,
            segment.start,
            segment.end,
            segment.radius_start,
            segment.radius_end,
            maturity,
            segment.depth,
        )
    }

    last_internode := make([]int, len(graph.axes))
    defer delete(last_internode)
    for &value in last_internode do value = -1
    for internode, internode_index in graph.internodes do last_internode[internode.axis] = internode_index
    for axis, axis_index in graph.axes {
        terminal := last_internode[axis_index]
        if terminal < 0 do continue
        state := maturity < 1 && axis.active ? Bud_State.Continuing : Bud_State.Terminated
        append(&graph.buds, Bud{terminal, state, axis.vigor})
    }

    for leaf in source.leaves {
        nearest := -1
        nearest_distance := f32(3.402823e38)
        nearest_fraction := f32(1)
        for segment, segment_index in source.segments {
            direction := segment.end - segment.start
            length_squared := linalg.dot(direction, direction)
            fraction := f32(0)
            if length_squared > 1e-10 {
                fraction = clamp(linalg.dot(leaf.position - segment.start, direction) / length_squared, f32(0), f32(1))
            }
            point := segment.start + direction * fraction
            delta := leaf.position - point
            distance := linalg.dot(delta, delta)
            if distance < nearest_distance {
                nearest = segment_index
                nearest_distance = distance
                nearest_fraction = fraction
            }
        }
        if nearest >= 0 {
            graph_add_organ(&graph, nearest, nearest_fraction, .Leaf, leaf.forward, leaf.up, 0, leaf.depth)
        }
    }
    return graph
}

graph_compile :: proc(graph: ^Plant_Graph) -> plant_structure.Interpret_Result {
    result: plant_structure.Interpret_Result
    if graph == nil do return result
    for internode in graph.internodes {
        append(
            &result.plant.segments,
            plant_structure.Segment {
                internode.start,
                internode.end,
                internode.radius_start,
                internode.radius_end,
                internode.render_depth,
            },
        )
    }
    for organ in graph.organs {
        if organ.internode < 0 || organ.internode >= len(graph.internodes) do continue
        internode := graph.internodes[organ.internode]
        position := internode.start + (internode.end - internode.start) * clamp(organ.fraction, f32(0), f32(1))
        append(
            &result.plant.leaves,
            plant_structure.Attachment_Anchor{position, organ.forward, organ.up, organ.render_depth},
        )
    }
    return result
}

canonicalize_architecture :: proc(source: ^plant_structure.Interpret_Result, species: Species = .Olive, maturity: f32 = 1) {
    if source == nil || source.error != .None do return
    graph := graph_from_interpreted(&source.plant, species, maturity)
    compiled := graph_compile(&graph)
    destroy_graph(&graph)
    plant_structure.destroy_plant(&source.plant)
    source.plant = compiled.plant
    source.error = compiled.error
}
