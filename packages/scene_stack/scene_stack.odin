package scene_stack

// A presentation-neutral scene stack.
//
// The stack is the pushdown store of a small pushdown automaton: commands are
// input symbols, the top scene is the current state, and lifecycle callbacks
// are the transition actions. Loading happens in a staging slot so a scene can
// be prepared without interrupting the scene currently on screen.

Load_State :: enum {
    Pending,
    Ready,
    Failed,
}

Transition_Phase :: enum {
    Idle,
    Loading,
    Out,
    In,
}

Operation :: enum {
    None,
    Push,
    Pop,
    Swap,
}

Context :: struct {
    data: rawptr,
}

Load_Proc :: proc(instance: ^Scene_Instance, ctx: ^Context) -> Load_State
Unload_Proc :: proc(instance: ^Scene_Instance, ctx: ^Context)
Enter_Proc :: proc(instance: ^Scene_Instance, ctx: ^Context)
Suspend_Proc :: proc(instance: ^Scene_Instance, ctx: ^Context)
Resume_Proc :: proc(instance: ^Scene_Instance, ctx: ^Context)
Exit_Proc :: proc(instance: ^Scene_Instance, ctx: ^Context)
Update_Proc :: proc(instance: ^Scene_Instance, ctx: ^Context, delta_seconds: f32)

Definition :: struct {
    id:      string,
    load:    Load_Proc,
    unload:  Unload_Proc,
    enter:   Enter_Proc,
    suspend: Suspend_Proc,
    resume:  Resume_Proc,
    exit:    Exit_Proc,
    update:  Update_Proc,
}

Scene_Instance :: struct {
    definition: ^Definition,
    data:       rawptr,
    load_state: Load_State,
    loaded:     bool,
}

Transition :: struct {
    operation: Operation,
    phase:     Transition_Phase,
    elapsed:   f32,
    duration:  f32,
}

Stack :: struct {
    scenes:            [dynamic]Scene_Instance,
    ctx:               Context,
    transition:        Transition,
    pending_operation: Operation,
    pending_scene:     Scene_Instance,
    pending_active:    bool,
}

default_transition :: proc(duration := f32(.2)) -> Transition {
    return {operation = .None, phase = .Idle, duration = scene_stack_max_f32(0, duration)}
}

new :: proc(ctx := Context{}, transition := Transition{phase = .Idle, operation = .None, duration = .2}) -> Stack {
    return {ctx = ctx, transition = transition}
}

destroy :: proc(stack: ^Stack) {
    if stack == nil do return
    for &scene in stack.scenes {
        if scene.loaded && scene.definition != nil && scene.definition.unload != nil {
            scene.definition.unload(&scene, &stack.ctx)
        }
    }
    if stack.pending_active &&
       stack.pending_scene.loaded &&
       stack.pending_scene.definition != nil &&
       stack.pending_scene.definition.unload != nil {
        stack.pending_scene.definition.unload(&stack.pending_scene, &stack.ctx)
    }
    delete(stack.scenes)
    stack^ = {}
}

top :: proc(stack: ^Stack) -> ^Scene_Instance {
    if stack == nil || len(stack.scenes) == 0 do return nil
    return &stack.scenes[len(stack.scenes) - 1]
}

depth :: proc(stack: ^Stack) -> int {
    if stack == nil do return 0
    return len(stack.scenes)
}

is_busy :: proc(stack: ^Stack) -> bool {
    return stack != nil && (stack.pending_active || stack.transition.phase != .Idle)
}

request_push :: proc(stack: ^Stack, definition: ^Definition, data: rawptr = nil) -> bool {
    return request_scene(stack, .Push, definition, data)
}

request_swap :: proc(stack: ^Stack, definition: ^Definition, data: rawptr = nil) -> bool {
    if stack == nil || len(stack.scenes) == 0 do return false
    return request_scene(stack, .Swap, definition, data)
}

request_pop :: proc(stack: ^Stack) -> bool {
    if stack == nil || len(stack.scenes) == 0 || is_busy(stack) do return false
    stack.pending_operation = .Pop
    stack.pending_active = true
    return true
}

request_scene :: proc(stack: ^Stack, operation: Operation, definition: ^Definition, data: rawptr) -> bool {
    if stack == nil || definition == nil || len(definition.id) == 0 || definition.load == nil || is_busy(stack) do return false
    stack.pending_operation = operation
    stack.pending_scene = {
        definition = definition,
        data       = data,
        load_state = .Pending,
    }
    stack.pending_active = true
    return true
}

call_load :: proc(stack: ^Stack) -> bool {
    scene := &stack.pending_scene
    result := scene.definition.load(scene, &stack.ctx)
    scene.load_state = result
    if result == .Failed {
        scene.loaded = false
        return false
    }
    scene.loaded = result == .Ready
    return scene.loaded
}

call_unload :: proc(stack: ^Stack, scene: ^Scene_Instance) {
    if scene != nil && scene.loaded && scene.definition != nil && scene.definition.unload != nil {
        scene.definition.unload(scene, &stack.ctx)
    }
    if scene != nil do scene.loaded = false
}

start_transition :: proc(stack: ^Stack, phase: Transition_Phase) {
    stack.transition.operation = stack.pending_operation
    stack.transition.phase = phase
    stack.transition.elapsed = 0
}

begin_out :: proc(stack: ^Stack) {
    start_transition(stack, .Out)
    if stack.transition.duration == 0 {
        commit_pending(stack)
        finish_transition(stack)
    }
}

commit_pending :: proc(stack: ^Stack) {
    operation := stack.pending_operation
    switch operation {
    case .None:
    case .Push:
        if previous := top(stack); previous != nil && previous.definition.suspend != nil {
            previous.definition.suspend(previous, &stack.ctx)
        }
        append(&stack.scenes, stack.pending_scene)
        current := top(stack)
        if current.definition.enter != nil do current.definition.enter(current, &stack.ctx)
    case .Swap:
        if previous := top(stack); previous != nil {
            if previous.definition.exit != nil do previous.definition.exit(previous, &stack.ctx)
            call_unload(stack, previous)
            pop(&stack.scenes)
        }
        append(&stack.scenes, stack.pending_scene)
        current := top(stack)
        if current.definition.enter != nil do current.definition.enter(current, &stack.ctx)
    case .Pop:
        if previous := top(stack); previous != nil {
            if previous.definition.exit != nil do previous.definition.exit(previous, &stack.ctx)
            call_unload(stack, previous)
            pop(&stack.scenes)
        }
        if current := top(stack); current != nil && current.definition.resume != nil {
            current.definition.resume(current, &stack.ctx)
        }
    }
    stack.pending_scene = {}
    stack.pending_operation = .None
    stack.pending_active = false
}

finish_transition :: proc(stack: ^Stack) {
    stack.transition.phase = .Idle
    stack.transition.operation = .None
    stack.transition.elapsed = 0
}

update :: proc(stack: ^Stack, delta_seconds: f32) {
    if stack == nil do return
    dt := scene_stack_max_f32(0, delta_seconds)

    if current := top(stack); current != nil && stack.transition.phase == .Idle && current.definition.update != nil {
        current.definition.update(current, &stack.ctx, dt)
    }

    if stack.pending_active && stack.transition.phase == .Idle {
        if stack.pending_operation == .Pop {
            begin_out(stack)
        } else if !call_load(stack) {
            if stack.pending_scene.load_state == .Pending {
                start_transition(stack, .Loading)
                return
            } else {
                call_unload(stack, &stack.pending_scene)
                stack.pending_scene = {}
                stack.pending_operation = .None
                stack.pending_active = false
                finish_transition(stack)
            }
        } else {
            begin_out(stack)
        }
    }

    switch stack.transition.phase {
    case .Idle:
    case .Loading:
        if call_load(stack) do begin_out(stack)
    case .Out, .In:
        stack.transition.elapsed += dt
        duration := stack.transition.duration
        if duration == 0 || stack.transition.elapsed >= duration {
            if stack.transition.phase == .Out {
                commit_pending(stack)
                stack.transition.elapsed = 0
                stack.transition.phase = .In
            } else {
                finish_transition(stack)
            }
        }
    }
}

transition_progress :: proc(stack: ^Stack) -> f32 {
    if stack == nil do return 0
    if stack.transition.phase == .Idle do return 0
    if stack.transition.duration <= 0 do return 1
    return clamp(stack.transition.elapsed / stack.transition.duration, 0, 1)
}

scene_stack_max_f32 :: proc(a, b: f32) -> f32 {
    if a > b do return a
    return b
}
