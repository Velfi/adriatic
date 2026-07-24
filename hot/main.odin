package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

HOT_ABI_VERSION :: 1
HOT_LOAD_ATTEMPTS :: 12
HOT_LOAD_RETRY_DELAY :: 25 * time.Millisecond

Hot_API :: struct {
    lib:         dynlib.Library,
    run:         proc() -> bool,
    abi_version: proc() -> u64,
}

hot_path :: proc(directory, name: string) -> string {
    return fmt.tprintf("%s/%s", directory, name)
}

hot_load :: proc(source_path, copy_path: string) -> (api: Hot_API, ok: bool) {
    for attempt in 0 ..< HOT_LOAD_ATTEMPTS {
        if copy_error := os.copy_file(copy_path, source_path); copy_error == nil {
            _, symbols_ok := dynlib.initialize_symbols(&api, copy_path, "_", "lib")
            if symbols_ok && api.run != nil && api.abi_version != nil {
                if api.abi_version() == HOT_ABI_VERSION {
                    return api, true
                }
                fmt.eprintln("adriatic hot reload rejected: ABI changed")
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
    for api_version := 0;; api_version += 1 {
        copy_path := hot_path(
            executable_directory,
            fmt.tprintf("adriatic_%d.%s", api_version, dynlib.LIBRARY_FILE_EXTENSION),
        )
        api, ok := hot_load(source_path, copy_path)
        if !ok do return
        restart := api.run()
        hot_unload(&api, copy_path)
        if !restart do return
    }
}
