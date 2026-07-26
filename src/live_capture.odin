package main

import "core:fmt"
import "core:os"
import "core:strings"
import rl "zelda_engine:canvas2d"

LIVE_CAPTURE_REQUEST_ENV :: "ADRIATIC_LIVE_CAPTURE_REQUEST"
LIVE_CAPTURE_DEFAULT_REQUEST_PATH :: "build/live-capture.request"

live_capture_request_path :: proc() -> string {
    path := os.get_env(LIVE_CAPTURE_REQUEST_ENV, context.temp_allocator)
    if path != "" do return path
    return LIVE_CAPTURE_DEFAULT_REQUEST_PATH
}

live_capture_poll :: proc() {
    request_path := live_capture_request_path()
    if !os.exists(request_path) do return
    data, read_error := os.read_entire_file_from_path(request_path, context.temp_allocator)
    if read_error != nil do return
    target_path := strings.trim_space(string(data))
    if target_path == "" {
        _ = os.remove(request_path)
        return
    }
    rl.TakeScreenshot(fmt.ctprintf("%s", target_path))
    _ = os.remove(request_path)
}
