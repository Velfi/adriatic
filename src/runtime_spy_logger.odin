package main

import hot_abi "../packages/hot_abi"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import spy "zelda_engine:spy"

adriatic_file_log_open :: proc(allocator := context.allocator) -> (file: ^os.File, path: string) {
    datetime, datetime_ok := time.time_to_datetime(time.now())
    if !datetime_ok do return

    temporary_path := fmt.tprintf(
        "/tmp/adriatic-%04d-%02d-%02dT%02d-%02d-%02d.%09dZ.log",
        datetime.year,
        int(datetime.month),
        int(datetime.day),
        int(datetime.hour),
        int(datetime.minute),
        int(datetime.second),
        datetime.nano,
    )
    path = strings.clone(temporary_path, allocator)
    created_file, create_error := os.create(path)
    if create_error != nil {
        delete(path, allocator)
        path = ""
        return
    }
    file = created_file
    return
}

adriatic_run :: proc(
    persistent_canvas_state: rawptr,
    args: []string = os.args,
    request: ^Capture_Request = nil,
    startup_started_at: time.Tick = {},
) -> hot_abi.Run_Result {
    allocator := context.allocator
    console_options := spy.Default_Console_Logger_Opts - {.Time}
    console_logger := spy.create_console_logger(.Info, console_options, alloc = allocator)
    console_layer, console_installed := spy.add_global_subscriber_layer_with_id(console_logger)
    defer spy.destroy_console_logger(console_logger, allocator)
    defer if console_installed do _ = spy.remove_global_subscriber_layer_by_id(console_layer)

    file_handle, file_path := adriatic_file_log_open(allocator)
    file_logger: spy.Logger
    file_layer: spy.Subscriber_Layer_Id
    file_installed := false
    if file_handle == nil {
        spy.warn("file logging unavailable")
    } else {
        file_logger = spy.create_file_logger(file_handle, .Debug, alloc = allocator)
        file_layer, file_installed = spy.add_global_subscriber_layer_with_id(file_logger)
        spy.info("file log=", file_path)
    }
    defer if file_path != "" do delete(file_path, allocator)
    defer if file_handle != nil do spy.destroy_file_logger(file_logger, allocator)
    defer if file_installed do _ = spy.remove_global_subscriber_layer_by_id(file_layer)

    return adriatic_run_impl(persistent_canvas_state, args, request, startup_started_at)
}
