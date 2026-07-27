package main

import hot_abi "../packages/hot_abi"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

HOT_LOAD_ATTEMPTS :: 12
HOT_LOAD_RETRY_DELAY :: 25 * time.Millisecond
HOT_LIBRARY_ENV :: "ADRIATIC_HOT_LIBRARY"
HOT_STATE_ENV :: "ADRIATIC_HOT_STATE"

Hot_API :: struct {
    lib:                      dynlib.Library,
    run:                      proc(_: rawptr) -> hot_abi.Run_Result,
    abi_version:              proc() -> u64,
    canvas_state:             proc() -> rawptr,
    canvas_state_abi_version: proc() -> u64,
    close_canvas:             proc(),
}

hot_path :: proc(directory, name: string) -> string {
    return fmt.tprintf("%s/%s", directory, name)
}

hot_load :: proc(source_path, copy_path: string) -> (api: Hot_API, ok: bool) {
    for attempt in 0 ..< HOT_LOAD_ATTEMPTS {
        if copy_error := os.copy_file(copy_path, source_path); copy_error == nil {
            count, symbols_ok := dynlib.initialize_symbols(&api, copy_path, "", "lib")
            if symbols_ok &&
               api.run != nil &&
               api.abi_version != nil &&
               api.canvas_state != nil &&
               api.canvas_state_abi_version != nil &&
               api.close_canvas != nil {
                actual_abi := api.abi_version()
                expected_abi := hot_abi.type_hash(hot_abi.Contract)
                if actual_abi == expected_abi {
                    return api, true
                }
                fmt.eprintln(
                    "adriatic hot reload rejected: ABI changed (",
                    actual_abi,
                    " != ",
                    expected_abi,
                    ", symbols=",
                    count,
                    ")",
                )
            }
            if api.lib != nil {
                dynlib.unload_library(api.lib)
                api.lib = nil
            }
        }
        if attempt + 1 < HOT_LOAD_ATTEMPTS do time.sleep(HOT_LOAD_RETRY_DELAY)
    }
    fmt.eprintln("adriatic hot reload failed to load ", source_path)
    return
}

hot_unload :: proc(api: ^Hot_API, copy_path: string) {
    if api.lib != nil do dynlib.unload_library(api.lib)
    api^ = {}
    _ = os.remove(copy_path)
}

main :: proc() {
    executable_directory, directory_error := os.get_executable_directory(context.allocator)
    if directory_error != nil {
        fmt.eprintln("adriatic hot loader cannot find executable directory: ", directory_error)
        return
    }

    dll_name := "adriatic." + dynlib.LIBRARY_FILE_EXTENSION
    source_path := hot_path(executable_directory, dll_name)
    state_path := hot_path(executable_directory, "adriatic.hotstate")
    _ = os.set_env(HOT_LIBRARY_ENV, source_path)
    _ = os.set_env(HOT_STATE_ENV, state_path)
    api_version := 0
    copy_path := hot_path(
        executable_directory,
        fmt.tprintf("adriatic_%d.%s", api_version, dynlib.LIBRARY_FILE_EXTENSION),
    )
    api, ok := hot_load(source_path, copy_path)
    if !ok do return

    persistent_canvas_state: rawptr
    persistent_canvas_state_abi: u64
    for {
        result := api.run(persistent_canvas_state)
        persistent_canvas_state = api.canvas_state()
        persistent_canvas_state_abi = api.canvas_state_abi_version()
        if result == .Quit {
            hot_unload(&api, copy_path)
            return
        }

        api_version += 1
        next_copy_path := hot_path(
            executable_directory,
            fmt.tprintf("adriatic_%d.%s", api_version, dynlib.LIBRARY_FILE_EXTENSION),
        )
        next_api, next_ok := hot_load(source_path, next_copy_path)
        if !next_ok {
            api.close_canvas()
            hot_unload(&api, copy_path)
            return
        }

        if result != .Restart &&
           persistent_canvas_state != nil &&
           next_api.canvas_state_abi_version() != persistent_canvas_state_abi {
            // State layout changed. Old code must close the retained window
            // before the new module starts with a fresh engine state.
            api.close_canvas()
            persistent_canvas_state = nil
            persistent_canvas_state_abi = 0
        }
        if result == .Restart {
            _ = os.remove(state_path)
            persistent_canvas_state = nil
            persistent_canvas_state_abi = 0
        }

        hot_unload(&api, copy_path)
        api = next_api
        copy_path = next_copy_path
    }
}
