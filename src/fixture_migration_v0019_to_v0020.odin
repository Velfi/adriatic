package main

import fixture_v0019 "../packages/fixture_history/v0019"
import vehicles "../packages/vehicles"
import "core:mem"

FIXTURE_MIGRATION_V0019_TO_V0020_FROM_VERSION :: 19
FIXTURE_MIGRATION_V0019_TO_V0020_TO_VERSION :: 20
FIXTURE_MIGRATION_V0019_TO_V0020_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/vehicles.Car_Drive_State.racer",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:packages/vehicles.Car_Drive_Tune.racer",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:src.Fixture.car_handling_model",
		kind = .Scripted,
	},
}

fixture_migrate_v0019_to_v0020 :: proc(
	#by_ptr historical: fixture_v0019.Fixture,
	tentative: ^Fixture,
	allocator: mem.Allocator,
) -> Fixture_Migration_Error {
	_ = historical
	_ = allocator
	if tentative == nil do return {kind = .Invalid_Argument}

	// Existing saves predate the selector and therefore retain the exact model
	// they were authored with. Racer runtime is intentionally inactive until a
	// player initiates a drift after loading.
	tentative.car_handling_model = .Current_Physics
	tentative.car_drive.racer = {}
	tentative.tweak.car.racer = vehicles.CAR_DRIVE_SEDAN_TUNE.racer
	return {}
}
