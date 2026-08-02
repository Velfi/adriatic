package main

import hot_abi "../packages/hot_abi"
import "core:os"
import "core:time"
import spy "zelda_engine:spy"

adriatic_run :: proc(
    persistent_canvas_state: rawptr,
    args: []string = os.args,
    request: ^Capture_Request = nil,
    startup_started_at: time.Tick = {},
) -> hot_abi.Run_Result {
    allocator := context.allocator
    logger := spy.create_console_logger(.Debug, alloc = allocator)
    layer, installed := spy.add_global_subscriber_layer_with_id(logger)
    defer spy.destroy_console_logger(logger, allocator)
    defer if installed do _ = spy.remove_global_subscriber_layer_by_id(layer)
    return adriatic_run_impl(persistent_canvas_state, args, request, startup_started_at)
}
