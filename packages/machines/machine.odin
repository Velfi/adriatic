package machines

// Product rules for physical maintenance.  This package deliberately models no
// scene graph, input device, animation, or inventory UI: callers supply a tool
// id and turn the returned events into their own presentation and game state.

Gesture :: enum {
    Linear,
    Hinge,
    Rotary,
    Pump,
    Crank,
    Latch,
    Cable,
    Detach,
}
Evidence_Kind :: enum {
    Visual,
    Sound,
    Resistance,
    Leak,
    Heat,
    Alignment,
    Motion,
}
Event :: enum {
    None,
    Tool_Required,
    Work_Established,
    Verification_Required,
    Repair_Completed,
}

Evidence :: struct {
    id, part_id: string,
    kind:        Evidence_Kind,
    reveal_at:   f32,
}
Verification :: struct {
    id, handle_id:  string,
    minimum_travel: f32,
}
Procedure_Step :: struct {
    id, handle_id, required_tool_id:    string,
    gesture:                            Gesture,
    threshold:                          f32,
    world_minutes, montage_repetitions: int,
    result_tag:                         string,
}
Physical_Procedure :: struct {
    id, vehicle_id, fault_id: string,
    evidence:                 Evidence,
    step:                     Procedure_Step,
    verification:             Verification,
}

// Handle is the simulation counterpart to ArchipelagoGame's MachinePartHandle.
// Pose application belongs to the owning renderer or ECS transform system.
Handle :: struct {
    id, required_tool_id:                         string,
    gesture:                                      Gesture,
    range, resistance, completion_travel, travel: f32,
    reversible, deferred_completion, completed:   bool,
    unsuccessful_attempts:                        int,
}

Active_Procedure :: struct {
    procedure_index, step_index:           int,
    step_progress, montage_progress:       f32,
    awaiting_verification, montage_active: bool,
}

new_handle :: proc(
    id: string,
    gesture: Gesture,
    range: f32,
    required_tool_id := "",
    resistance := f32(.25),
    completion_travel := f32(.85),
    deferred_completion := false,
) -> Handle {
    return {
        id = id,
        required_tool_id = required_tool_id,
        gesture = gesture,
        range = range,
        resistance = resistance,
        completion_travel = completion_travel,
        reversible = true,
        deferred_completion = deferred_completion,
    }
}

apply_gesture :: proc(handle: ^Handle, amount, delta_seconds: f32, supplied_tool_id := "") -> Event {
    if handle == nil || delta_seconds <= 0 do return .None
    if len(handle.required_tool_id) > 0 && handle.required_tool_id != supplied_tool_id {
        handle.unsuccessful_attempts += 1
        return .Tool_Required
    }
    speed := lerp(1.8, .45, clamp(handle.resistance, 0, 1))
    handle.travel = clamp(handle.travel + amount * speed * delta_seconds, 0, 1)
    if !handle.completed && handle.travel >= handle.completion_travel {
        handle.completed = true
        if handle.deferred_completion do return .Work_Established
        return .Repair_Completed
    }
    return .None
}

restore_travel :: proc(handle: ^Handle, travel: f32) {
    if handle == nil do return
    handle.travel = clamp(travel, 0, 1)
    handle.completed = handle.travel >= handle.completion_travel
}

commit_completion :: proc(handle: ^Handle) -> bool {
    if handle == nil || !handle.completed do return false
    handle.deferred_completion = false
    return true
}

begin :: proc(active: ^Active_Procedure, procedure_index: int, current_travel: f32) {
    if active == nil do return
    active^ = {
        procedure_index = procedure_index,
        step_index      = 0,
        step_progress   = current_travel,
    }
}

// advance coordinates the work/verification state machine. `handle` is the
// currently manipulated part. Callers add `step.world_minutes` when this
// returns Verification_Required, and apply the repair when it returns
// Repair_Completed.
advance :: proc(
    active: ^Active_Procedure,
    procedure: Physical_Procedure,
    handle: ^Handle,
    amount, delta_seconds: f32,
    supplied_tool_id := "",
) -> Event {
    if active == nil || handle == nil do return .None
    step := procedure.step
    if active.montage_active {
        active.montage_progress = clamp(
            active.montage_progress + delta_seconds / max_f32(2.5, f32(step.montage_repetitions) * 1.2),
            0,
            1,
        )
        if active.montage_progress < 1 do return .None
        active.montage_active = false
        active.awaiting_verification = true
        return .Verification_Required
    }
    was_completed := handle.completed
    event := apply_gesture(handle, amount, delta_seconds, supplied_tool_id)
    active.step_progress = handle.travel
    if event == .Tool_Required || was_completed || !handle.completed do return event
    if active.awaiting_verification && handle.id == procedure.verification.handle_id {
        active.awaiting_verification = false
        active.step_progress = 1
        active.procedure_index = -1
        return .Repair_Completed
    }
    if step.montage_repetitions > 0 {
        active.montage_active = true
        return .Work_Established
    }
    active.awaiting_verification = true
    return .Verification_Required
}

find_procedure :: proc(procedures: []Physical_Procedure, vehicle_id, fault_id: string) -> (Physical_Procedure, bool) {
    for procedure in procedures {
        if procedure.vehicle_id == vehicle_id && procedure.fault_id == fault_id do return procedure, true
    }
    return {}, false
}

catalog :: proc() -> [28]Physical_Procedure {
    return {
        procedure(
            "aircraft_starter",
            "aircraft",
            "StuckStarterSolenoid",
            "starter_linkage",
            .Latch,
            "wrench",
            "reseated_starter",
            "starter_test",
            15,
        ),
        procedure(
            "aircraft_ignition",
            "aircraft",
            "IntermittentIgnition",
            "ignition_terminal",
            .Rotary,
            "wrench",
            "safety_wire",
            "engine_test",
            15,
        ),
        procedure(
            "aircraft_plugs",
            "aircraft",
            "FouledIgnition",
            "ignition_plug",
            .Detach,
            "plug_wrench",
            "cleaned_plugs",
            "engine_test",
            15,
        ),
        procedure(
            "aircraft_indicator",
            "aircraft",
            "StuckIndicator",
            "instrument_linkage",
            .Hinge,
            "",
            "freed_indicator",
            "control_test",
            15,
        ),
        procedure(
            "aircraft_cowling",
            "aircraft",
            "LooseCowling",
            "cowling_fastener",
            .Rotary,
            "wrench",
            "cowling_fastener",
            "engine_test",
            15,
        ),
        procedure(
            "aircraft_pump",
            "aircraft",
            "SluggishFuelPump",
            "wobble_pump",
            .Pump,
            "",
            "serviced_pump",
            "engine_test",
            15,
        ),
        procedure(
            "aircraft_fuel",
            "aircraft",
            "FuelContamination",
            "fuel_drain",
            .Rotary,
            "drain_glass",
            "drained_fuel",
            "engine_test",
            12,
        ),
        procedure(
            "aircraft_propeller",
            "aircraft",
            "PropellerBent",
            "propeller",
            .Rotary,
            "propeller_gauge",
            "repaired_propeller",
            "propeller_test",
            25,
        ),
        procedure(
            "aircraft_float",
            "aircraft",
            "FloatLeak",
            "float_pump",
            .Pump,
            "float_pump",
            "float_patch",
            "leak_test",
            25,
        ),
        procedure(
            "aircraft_controls",
            "aircraft",
            "ControlLinkageDamage",
            "bellcrank",
            .Rotary,
            "wrench",
            "mechanic_mark",
            "control_test",
            15,
        ),
        procedure(
            "aircraft_engine",
            "aircraft",
            "EngineOverheat",
            "cooling_shutter",
            .Hinge,
            "",
            "serviced_engine",
            "engine_test",
            20,
        ),
        procedure(
            "aircraft_worn_engine",
            "aircraft",
            "WornEngine",
            "engine_mount",
            .Detach,
            "wrench",
            "mismatched_part",
            "engine_test",
            30,
        ),
        procedure("dirtbike_lift", "dirtbike", "fallen", "lift", .Hinge, "", "scuffed_side", "push_test", 3),
        procedure(
            "dirtbike_fork",
            "dirtbike",
            "bent front fork",
            "fork_alignment",
            .Rotary,
            "tracking_bar",
            "fork_paint_mark",
            "push_test",
            12,
        ),
        procedure(
            "dirtbike_frame",
            "dirtbike",
            "bent frame",
            "frame_gauge",
            .Linear,
            "tracking_bar",
            "frame_measure_mark",
            "push_test",
            8,
        ),
        procedure(
            "dirtbike_engine",
            "dirtbike",
            "drowned engine",
            "kick_starter",
            .Crank,
            "",
            "cleared_engine",
            "engine_test",
            8,
        ),
        procedure(
            "dirtbike_brake",
            "dirtbike",
            "brake drag",
            "brake_adjuster",
            .Rotary,
            "wrench",
            "mismatched_lever",
            "wheel_test",
            8,
        ),
        procedure(
            "dirtbike_fuel",
            "dirtbike",
            "fuel system fault",
            "fuel_tap",
            .Rotary,
            "",
            "patched_fuel_line",
            "engine_test",
            8,
        ),
        procedure(
            "kettenkrad_track",
            "kettenkrad",
            "thrown track",
            "track_tensioner",
            .Crank,
            "track_wrench",
            "replacement_track_link",
            "crawl_test",
            40,
        ),
        procedure(
            "kettenkrad_heat",
            "kettenkrad",
            "coolant boiling",
            "radiator_shutter",
            .Hinge,
            "",
            "patched_radiator",
            "engine_test",
            25,
        ),
        procedure(
            "kettenkrad_bog",
            "kettenkrad",
            "bogged",
            "winch",
            .Crank,
            "winch_cable",
            "workshop_stencil",
            "crawl_test",
            25,
        ),
        procedure(
            "kettenkrad_brake",
            "kettenkrad",
            "steering brake",
            "brake_linkage",
            .Rotary,
            "wrench",
            "welded_guard",
            "crawl_test",
            15,
        ),
        procedure(
            "kettenkrad_clutch",
            "kettenkrad",
            "clutch slipping",
            "clutch_adjuster",
            .Rotary,
            "wrench",
            "clutch_mark",
            "crawl_test",
            15,
        ),
        procedure(
            "kettenkrad_torsion",
            "kettenkrad",
            "broken torsion bar",
            "torsion_fixture",
            .Latch,
            "jack",
            "torsion_brace",
            "crawl_test",
            25,
        ),
        procedure(
            "bicycle_chain",
            "bicycle",
            "dropped chain",
            "crank",
            .Crank,
            "",
            "replacement_chain_guard",
            "wheel_test",
            3,
        ),
        procedure(
            "bicycle_tire",
            "bicycle",
            "flat tire",
            "pump",
            .Pump,
            "bicycle_pump",
            "patched_tire",
            "squeeze_test",
            10,
        ),
        procedure(
            "bicycle_wheel",
            "bicycle",
            "bent wheel",
            "spoke_adjuster",
            .Rotary,
            "saddle_spanner",
            "wrapped_grip",
            "wheel_test",
            12,
        ),
        procedure("bicycle_frame", "bicycle", "bent frame", "frame_sight", .Linear, "", "frame_mark", "push_test", 3),
    }
}

procedure :: proc(
    id, vehicle_id, fault_id, handle_id: string,
    gesture: Gesture,
    tool_id, tag, verification_id: string,
    minutes: int,
) -> Physical_Procedure {
    kind := evidence_kind(fault_id)
    return {
        id = id,
        vehicle_id = vehicle_id,
        fault_id = fault_id,
        evidence = {id = id, part_id = handle_id, kind = kind, reveal_at = .35},
        step = {
            id = id,
            handle_id = handle_id,
            required_tool_id = tool_id,
            gesture = gesture,
            threshold = .85,
            world_minutes = minutes,
            montage_repetitions = montage_repetitions(minutes),
            result_tag = tag,
        },
        verification = {id = id, handle_id = verification_id, minimum_travel = .7},
    }
}

evidence_kind :: proc(fault_id: string) -> Evidence_Kind {
    if contains(fault_id, "leak") do return .Leak
    if contains(fault_id, "overheat") do return .Heat
    if contains(fault_id, "bent") || contains(fault_id, "linkage") do return .Alignment
    return .Sound
}

montage_repetitions :: proc(minutes: int) -> int {
    if minutes > 10 do return 3
    return 0
}

contains :: proc(value, needle: string) -> bool {
    if len(needle) > len(value) do return false
    for i in 0 ..< len(value) - len(needle) + 1 {
        if value[i:i + len(needle)] == needle do return true
    }
    return false
}

clamp :: proc(value, low, high: f32) -> f32 {
    if value < low do return low
    if value > high do return high
    return value
}

lerp :: proc(a, b, t: f32) -> f32 { return a + (b - a) * t }

max_f32 :: proc(a, b: f32) -> f32 {
    if a > b do return a
    return b
}
