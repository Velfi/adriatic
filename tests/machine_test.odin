package tests

import machines "../packages/machines"
import "core:testing"

@(test)
machine_catalog_ports_the_fleet_maintenance_contracts :: proc(t: ^testing.T) {
	procedures := machines.catalog()
	testing.expect(t, len(procedures) == 28)
	procedure, found := machines.find_procedure(procedures[:], "aircraft", "FloatLeak")
	testing.expect(t, found && procedure.step.handle_id == "float_pump")
	testing.expect(
		t,
		procedure.step.montage_repetitions == 3 && procedure.verification.handle_id == "leak_test",
	)
}

@(test)
tool_gated_handle_keeps_motion_bounded :: proc(t: ^testing.T) {
	handle := machines.new_handle("test", .Rotary, 1, "wrench", 0, .8)
	testing.expect(t, machines.apply_gesture(&handle, 1, 1, "rock") == .Tool_Required)
	testing.expect(t, handle.travel == 0 && handle.unsuccessful_attempts == 1)
	testing.expect(t, machines.apply_gesture(&handle, 1, 1, "wrench") == .Repair_Completed)
	testing.expect(t, handle.travel == 1 && handle.completed)
}

@(test)
physical_repair_requires_a_verification_gesture :: proc(t: ^testing.T) {
	procedures := machines.catalog()
	procedure, found := machines.find_procedure(procedures[:], "dirtbike", "fallen")
	testing.expect(t, found)
	work := machines.new_handle(
		procedure.step.handle_id,
		procedure.step.gesture,
		1,
		procedure.step.required_tool_id,
		0,
		procedure.step.threshold,
		true,
	)
	active: machines.Active_Procedure
	machines.begin(&active, 0, 0)
	testing.expect(t, machines.advance(&active, procedure, &work, 1, 1) == .Verification_Required)
	verification := machines.new_handle(
		procedure.verification.handle_id,
		.Latch,
		1,
		"",
		0,
		procedure.verification.minimum_travel,
	)
	testing.expect(
		t,
		machines.advance(&active, procedure, &verification, 1, 1) == .Repair_Completed,
	)
	testing.expect(t, machines.commit_completion(&work))
}
