package main

import fixture_v0004 "../packages/fixture_history/v0004"
import "core:mem"

FIXTURE_MIGRATION_V0004_TO_V0005_FROM_VERSION :: 4
FIXTURE_MIGRATION_V0004_TO_V0005_TO_VERSION :: 5
FIXTURE_MIGRATION_V0004_TO_V0005_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/flight.Body_State.angular_velocity_world",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/flight.Body_State.orientation",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/libellula.Runtime.spawn_orientation",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/postale.Runtime.ace_runtime",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/postale.Runtime.ace_tuning",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/postale.Runtime.flight_model",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/postale.Runtime.spawn_orientation",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-order:adriatic:packages/flight.Body_State",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-remove:adriatic:packages/flight.Body_State.angular_velocity",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-remove:adriatic:packages/flight.Body_State.basis",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-remove:adriatic:packages/libellula.Runtime.spawn_basis",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-remove:adriatic:packages/libellula.Runtime.telemetry",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-remove:adriatic:packages/postale.Runtime.spawn_basis",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-remove:adriatic:packages/postale.Runtime.telemetry",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "field-remove:adriatic:src.Fixture.camera_target_lock",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "type-remove:adriatic:packages/flight.Telemetry",
		kind = .Unresolved,
	},
	Fixture_Migration_Resolution {
		change_id = "type-remove:adriatic:packages/flight.Tri_Rotor_Telemetry",
		kind = .Unresolved,
	},
}

fixture_migrate_v0004_to_v0005 :: proc(
	#by_ptr historical: fixture_v0004.Fixture,
	tentative: ^Fixture,
	allocator: mem.Allocator,
) -> Fixture_Migration_Error {
	_ = historical
	_ = tentative
	_ = allocator
	return Fixture_Migration_Error{kind = .Unresolved}
}
