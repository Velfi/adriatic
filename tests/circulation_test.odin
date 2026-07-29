package tests

import circulation "../packages/circulation"
import roads "../packages/roads"
import "core:math"
import "core:testing"

@(test)
circulation_area_contains_rotated_rectangles :: proc(t: ^testing.T) {
    area := circulation.Area {
        center_x = 10,
        center_z = 20,
        width    = 4,
        length   = 12,
        rotation = math.PI * .5,
    }
    testing.expect(t, circulation.area_contains(area, 15, 20))
    testing.expect(t, !circulation.area_contains(area, 10, 25))
    testing.expect(t, circulation.area_distance(area, 17, 20) > 0)
}

@(test)
circulation_plazas_are_passages_and_overlap_crossing_streets :: proc(t: ^testing.T) {
    plaza := circulation.Area {
        center_x = 10,
        center_z = 20,
        width    = 18,
        length   = 12,
        kind     = .Plaza,
    }
    crossing := circulation.Area {
        center_x = 10,
        center_z = 20,
        width    = 30,
        length   = 5,
        rotation = math.PI * .5,
        kind     = .Street,
    }
    clear := crossing
    clear.center_x = 40

    testing.expect(t, circulation.area_is_passage(plaza.kind))
    testing.expect(t, circulation.area_overlaps(plaza, crossing))
    testing.expect(t, !circulation.area_overlaps(plaza, clear))
    nearest_x, nearest_z := circulation.area_nearest_point(plaza, 10, 40)
    testing.expect_value(t, nearest_x, f32(10))
    testing.expect_value(t, nearest_z, f32(26))
}

@(test)
circulation_query_unifies_authored_edges_and_generated_areas :: proc(t: ^testing.T) {
    graph: roads.Graph
    from := roads.add_node(&graph, {0, 2, 0})
    to := roads.add_node(&graph, {20, 2, 0})
    _ = roads.add_straight_edge(&graph, from, to, 6, 1, .Asphalt)

    plan: circulation.Plan
    _ = circulation.plan_add(
        &plan,
        {
            center_x = 10,
            center_z = 20,
            width = 20,
            length = 4,
            kind = .Path,
            source = .Derived,
            pavement = .Cobblestone,
            walkable = true,
        },
    )

    road_hit := circulation.surface_at(&graph, &plan, {10, 2, 1})
    testing.expect(t, road_hit.on_surface)
    testing.expect(t, road_hit.from_authored)
    testing.expect(t, road_hit.pavement == .Asphalt)
    testing.expect(t, road_hit.driveable)

    path_hit := circulation.surface_at(&graph, &plan, {10, 2, 20})
    testing.expect(t, path_hit.on_surface)
    testing.expect(t, !path_hit.from_authored)
    testing.expect(t, path_hit.kind == .Path)
    testing.expect(t, path_hit.walkable)
    testing.expect(t, !path_hit.driveable)
}
