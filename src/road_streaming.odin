package main

import fixture_file "../packages/fixture_file"
import hs "zelda_engine:hs"
import roads "../packages/roads"
import rt "base:runtime"
import "core:hash"
import "core:mem"
import "core:os"
import "core:sync"
import "core:thread"

ROAD_STREAM_QUEUE_CAPACITY :: 256

Road_Stream_Error :: enum u8 {
    None,
    Invalid_Record,
    Read,
    Checksum,
    Decode,
    Queue_Full,
    Stopped,
}

Road_Stream_Request :: struct {
    key:        roads.Tile_Key,
    entry:      fixture_file.Section_Entry,
    generation: u64,
}

Road_Stream_Completion :: struct {
    key:        roads.Tile_Key,
    tile:       ^roads.Tile,
    generation: u64,
    error:      Road_Stream_Error,
}

Road_Stream_Runtime :: struct {
    file:             ^os.File,
    worker:           ^thread.Thread,
    allocator:        mem.Allocator,
    mutex:            sync.Mutex,
    wake:             sync.Cond,
    completion_space: sync.Cond,
    stopping:         bool,
    requests:         [ROAD_STREAM_QUEUE_CAPACITY]Road_Stream_Request,
    request_head:     int,
    request_count:    int,
    completions:      [ROAD_STREAM_QUEUE_CAPACITY]Road_Stream_Completion,
    completion_head:  int,
    completion_count: int,
}

road_stream_worker_main :: proc(t: ^thread.Thread) {
    runtime := cast(^Road_Stream_Runtime)t.data
    if runtime == nil do return
    for {
        sync.mutex_lock(&runtime.mutex)
        for runtime.request_count == 0 && !runtime.stopping {
            sync.cond_wait(&runtime.wake, &runtime.mutex)
        }
        if runtime.stopping {
            sync.mutex_unlock(&runtime.mutex)
            return
        }
        request := runtime.requests[runtime.request_head]
        runtime.requests[runtime.request_head] = {}
        runtime.request_head = (runtime.request_head + 1) % ROAD_STREAM_QUEUE_CAPACITY
        runtime.request_count -= 1
        sync.mutex_unlock(&runtime.mutex)

        completion := Road_Stream_Completion {
            key        = request.key,
            generation = request.generation,
        }
        if request.entry.key.kind != .Road_Tile ||
           request.entry.key.x != request.key.x ||
           request.entry.key.z != request.key.z ||
           request.entry.size == 0 ||
           request.entry.size > u64(roads.ROAD_TILE_RECORD_MAX_BYTES) ||
           request.entry.offset > u64(max(i64)) {
            completion.error = .Invalid_Record
        } else {
            bytes, allocation_error := make([]byte, int(request.entry.size), runtime.allocator)
            if allocation_error != nil {
                completion.error = .Decode
            } else {
                read, read_error := os.read_at(runtime.file, bytes, i64(request.entry.offset))
                if read_error != nil || read != len(bytes) {
                    completion.error = .Read
                } else if hash.fnv64a(bytes) != request.entry.checksum {
                    completion.error = .Checksum
                } else {
                    tile, decode_error, decoded := roads.tile_decode(bytes, runtime.allocator)
                    hs.portable_error_dispose(&decode_error)
                    if decoded {
                        completion.tile = tile
                    } else {
                        completion.error = .Decode
                    }
                }
                delete(bytes, runtime.allocator)
            }
        }

        sync.mutex_lock(&runtime.mutex)
        if runtime.stopping {
            sync.mutex_unlock(&runtime.mutex)
            if completion.tile != nil do roads.tile_destroy(completion.tile, runtime.allocator)
            return
        }
        for runtime.completion_count >= ROAD_STREAM_QUEUE_CAPACITY && !runtime.stopping {
            sync.cond_wait(&runtime.completion_space, &runtime.mutex)
        }
        if runtime.stopping {
            sync.mutex_unlock(&runtime.mutex)
            if completion.tile != nil do roads.tile_destroy(completion.tile, runtime.allocator)
            return
        }
        tail := (runtime.completion_head + runtime.completion_count) % ROAD_STREAM_QUEUE_CAPACITY
        runtime.completions[tail] = completion
        runtime.completion_count += 1
        sync.mutex_unlock(&runtime.mutex)
    }
}

road_stream_open :: proc(runtime: ^Road_Stream_Runtime, path: string, allocator := context.allocator) -> bool {
    if runtime == nil || path == "" || allocator.procedure == nil do return false
    // Opening an active runtime would orphan its file and worker. Call close
    // before reusing it so shutdown and queue ownership stay deterministic.
    if runtime.file != nil || runtime.worker != nil do return false
    runtime^ = {}
    file, open_error := os.open(path, {.Read})
    if open_error != nil || file == nil do return false
    runtime.file = file
    // Tile decoding happens on the worker while completed tiles are consumed
    // on the main thread, so use the process allocator rather than an
    // arbitrary caller allocator that may be thread-confined.
    runtime.allocator = rt.default_allocator()
    worker := thread.create(road_stream_worker_main, .Low)
    if worker == nil {
        _ = os.close(file)
        runtime^ = {}
        return false
    }
    worker.data = rawptr(runtime)
    runtime.worker = worker
    thread.start(worker)
    return true
}

road_stream_request :: proc(
    runtime: ^Road_Stream_Runtime,
    key: roads.Tile_Key,
    entry: fixture_file.Section_Entry,
    generation: u64,
) -> Road_Stream_Error {
    if runtime == nil || runtime.worker == nil do return .Stopped
    sync.mutex_lock(&runtime.mutex)
    defer sync.mutex_unlock(&runtime.mutex)
    if runtime.stopping do return .Stopped
    if runtime.request_count >= ROAD_STREAM_QUEUE_CAPACITY do return .Queue_Full
    for offset in 0 ..< runtime.request_count {
        index := (runtime.request_head + offset) % ROAD_STREAM_QUEUE_CAPACITY
        if runtime.requests[index].key == key && runtime.requests[index].generation == generation do return .None
    }
    tail := (runtime.request_head + runtime.request_count) % ROAD_STREAM_QUEUE_CAPACITY
    runtime.requests[tail] = {
        key        = key,
        entry      = entry,
        generation = generation,
    }
    runtime.request_count += 1
    sync.cond_signal(&runtime.wake)
    return .None
}

road_stream_poll :: proc(runtime: ^Road_Stream_Runtime) -> (Road_Stream_Completion, bool) {
    if runtime == nil do return {}, false
    sync.mutex_lock(&runtime.mutex)
    defer sync.mutex_unlock(&runtime.mutex)
    if runtime.completion_count == 0 do return {}, false
    completion := runtime.completions[runtime.completion_head]
    runtime.completions[runtime.completion_head] = {}
    runtime.completion_head = (runtime.completion_head + 1) % ROAD_STREAM_QUEUE_CAPACITY
    runtime.completion_count -= 1
    sync.cond_signal(&runtime.completion_space)
    return completion, true
}

road_stream_close :: proc(runtime: ^Road_Stream_Runtime) {
    if runtime == nil do return
    if runtime.worker != nil {
        sync.mutex_lock(&runtime.mutex)
        runtime.stopping = true
        sync.mutex_unlock(&runtime.mutex)
        sync.cond_broadcast(&runtime.wake)
        sync.cond_broadcast(&runtime.completion_space)
        thread.join(runtime.worker)
        thread.destroy(runtime.worker)
    }
    for offset in 0 ..< runtime.completion_count {
        index := (runtime.completion_head + offset) % ROAD_STREAM_QUEUE_CAPACITY
        if runtime.completions[index].tile != nil {
            roads.tile_destroy(runtime.completions[index].tile, runtime.allocator)
        }
    }
    if runtime.file != nil do _ = os.close(runtime.file)
    runtime^ = {}
}
