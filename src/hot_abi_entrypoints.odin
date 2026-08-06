package main

import hot_abi "zelda_engine:hot_abi"
import "core:os"
import "core:time"
import canvas2d "zelda_engine:canvas2d"

@(export)
abi_version :: proc() -> u64 {
    return hot_abi.type_hash(hot_abi.Contract)
}

@(export)
run :: proc(persistent_canvas_state: rawptr) -> hot_abi.Run_Result {
    return adriatic_run(persistent_canvas_state)
}

@(export)
canvas_state :: proc() -> rawptr {
    return canvas2d.PersistentState()
}

@(export)
canvas_state_abi_version :: proc() -> u64 {
    return canvas2d.State_Abi_Version()
}

@(export)
close_canvas :: proc() {
    canvas2d.DestroyPersistentState()
}

when !HOT_RELOAD {
    main :: proc() {
        startup_started_at := time.tick_now()
        handled, success := adriatic_cli(os.args)
        if handled {
            if !success do os.exit(1)
            return
        }
        _ = adriatic_run(nil, startup_started_at = startup_started_at)
        if startup_failed do os.exit(1)
    }
}
