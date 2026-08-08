package tests

import "core:testing"
import render_graph "zelda_engine:render_graph"

Render_Order :: struct {
    values: [4]int,
    count:  int,
}

record_pass :: proc(user_data: rawptr) {
    order := cast(^Render_Order)user_data
    order.values[order.count] = order.count + 1
    order.count += 1
}

@(test)
render_graph_executes_dependencies_before_dependents :: proc(t: ^testing.T) {
    graph: render_graph.Graph
    a := render_graph.add_pass(&graph, "sky", record_pass)
    b := render_graph.add_pass(&graph, "terrain", record_pass)
    c := render_graph.add_pass(&graph, "ui", record_pass)
    testing.expect(t, render_graph.depends_on(&graph, b, a))
    testing.expect(t, render_graph.depends_on(&graph, c, b))
    order: Render_Order
    testing.expect(t, render_graph.execute(&graph, &order))
    testing.expect(t, order.count == 3)
}

@(test)
render_graph_rejects_cycles :: proc(t: ^testing.T) {
    graph: render_graph.Graph
    a := render_graph.add_pass(&graph, "a", nil)
    b := render_graph.add_pass(&graph, "b", nil)
    testing.expect(t, render_graph.depends_on(&graph, a, b))
    testing.expect(t, render_graph.depends_on(&graph, b, a))
    testing.expect(t, !render_graph.execute(&graph, nil))
}
