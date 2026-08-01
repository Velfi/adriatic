package main

import fixture_v0016 "../packages/fixture_history/v0016"
import "core:mem"

FIXTURE_MIGRATION_V0016_TO_V0017_FROM_VERSION :: 16
FIXTURE_MIGRATION_V0016_TO_V0017_TO_VERSION :: 17
FIXTURE_MIGRATION_V0016_TO_V0017_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.alignment_kind",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.authored_profile",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.curvature_from",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.curvature_to",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.design_id",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.engineering_designed",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.policy_pavement",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.station_from",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.station_to",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.structure_kind",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.superelevation_from",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/roads.Edge.superelevation_to",
		kind = .Scripted,
	},
}

fixture_migrate_v0016_to_v0017 :: proc(
	#by_ptr historical: fixture_v0016.Fixture,
	tentative: ^Fixture,
	allocator: mem.Allocator,
) -> Fixture_Migration_Error {
	_ = historical
	_ = allocator
	if tentative == nil do return {kind = .Invalid_Argument}
	graph := &tentative.project.road_graph
	if graph.edge_count < 0 || graph.edge_count > len(graph.edges) {
		return {kind = .Invalid_Source, change_id = "field-add:adriatic:packages/roads.Edge.design_id"}
	}
	for &edge in graph.edges[:graph.edge_count] {
		// V16 roads always used cubic geometry fitted to terrain at render time,
		// with waterways detected automatically. Preserve that behavior exactly.
		edge.design_id = 0
		edge.alignment_kind = .Legacy_Bezier
		edge.station_from, edge.station_to = 0, 0
		edge.curvature_from, edge.curvature_to = 0, 0
		edge.superelevation_from, edge.superelevation_to = 0, 0
		edge.structure_kind = .Legacy_Automatic
		edge.engineering_designed = false
		edge.policy_pavement = edge.pavement
		edge.authored_profile = false
	}
	return fixture_v0017_validate_road_design(tentative)
}

fixture_v0017_validate_road_design :: proc(tentative: ^Fixture) -> Fixture_Migration_Error {
	if tentative == nil do return {kind = .Invalid_Argument}
	graph := &tentative.project.road_graph
	if graph.edge_count < 0 || graph.edge_count > len(graph.edges) {
		return {kind = .Invalid_Source, change_id = "field-add:adriatic:packages/roads.Edge.design_id"}
	}
	for edge in graph.edges[:graph.edge_count] {
		if !edge.engineering_designed &&
		   (edge.design_id != 0 || edge.alignment_kind != .Legacy_Bezier ||
		    edge.structure_kind != .Legacy_Automatic || edge.authored_profile) {
			return {kind = .Invalid_Source, change_id = "field-add:adriatic:packages/roads.Edge.engineering_designed"}
		}
		if edge.policy_pavement < .Asphalt || edge.policy_pavement > .Steps {
			return {kind = .Invalid_Source, change_id = "field-add:adriatic:packages/roads.Edge.policy_pavement"}
		}
	}
	return {}
}
