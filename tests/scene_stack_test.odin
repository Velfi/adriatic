package tests

import scene_stack "../packages/scene_stack"
import "core:testing"

Scene_Test_State :: struct {
    loads, enters, suspends, resumes, exits, unloads, updates: int,
    load_ticks:                                                int,
}

scene_load :: proc(instance: ^scene_stack.Scene_Instance, ctx: ^scene_stack.Context) -> scene_stack.Load_State {
    state := cast(^Scene_Test_State)ctx.data
    state.loads += 1
    if state.load_ticks > 0 {
        state.load_ticks -= 1
        return .Pending
    }
    instance.data = ctx.data
    return .Ready
}

scene_unload :: proc(_: ^scene_stack.Scene_Instance, ctx: ^scene_stack.Context) {
    state := cast(^Scene_Test_State)ctx.data
    state.unloads += 1
}

scene_enter :: proc(_: ^scene_stack.Scene_Instance, ctx: ^scene_stack.Context) {
    state := cast(^Scene_Test_State)ctx.data
    state.enters += 1
}

scene_suspend :: proc(_: ^scene_stack.Scene_Instance, ctx: ^scene_stack.Context) {
    state := cast(^Scene_Test_State)ctx.data
    state.suspends += 1
}

scene_resume :: proc(_: ^scene_stack.Scene_Instance, ctx: ^scene_stack.Context) {
    state := cast(^Scene_Test_State)ctx.data
    state.resumes += 1
}

scene_exit :: proc(_: ^scene_stack.Scene_Instance, ctx: ^scene_stack.Context) {
    state := cast(^Scene_Test_State)ctx.data
    state.exits += 1
}

scene_update :: proc(_: ^scene_stack.Scene_Instance, ctx: ^scene_stack.Context, _: f32) {
    state := cast(^Scene_Test_State)ctx.data
    state.updates += 1
}

make_definition :: proc() -> scene_stack.Definition {
    return {
        id = "test",
        load = scene_load,
        unload = scene_unload,
        enter = scene_enter,
        suspend = scene_suspend,
        resume = scene_resume,
        exit = scene_exit,
        update = scene_update,
    }
}

@(test)
scene_stack_loads_before_swap_and_keeps_old_scene_active :: proc(t: ^testing.T) {
    state := Scene_Test_State {
        load_ticks = 1,
    }
    definition := make_definition()
    stack := scene_stack.new(scene_stack.Context{data = &state}, scene_stack.default_transition(0))
    defer scene_stack.destroy(&stack)

    testing.expect(t, scene_stack.request_push(&stack, &definition))
    scene_stack.update(&stack, 0)
    testing.expect(t, scene_stack.depth(&stack) == 0 && state.loads == 1)
    scene_stack.update(&stack, 0)
    testing.expect(t, scene_stack.depth(&stack) == 1 && state.enters == 1)

    state.load_ticks = 2
    testing.expect(t, scene_stack.request_swap(&stack, &definition))
    scene_stack.update(&stack, .1)
    testing.expect(t, scene_stack.depth(&stack) == 1 && state.exits == 0)
    scene_stack.update(&stack, .1)
    testing.expect(t, scene_stack.depth(&stack) == 1 && state.exits == 0)
    scene_stack.update(&stack, .1)
    testing.expect(t, state.exits == 1 && state.enters == 2)
}

@(test)
scene_stack_push_and_pop_suspend_and_resume :: proc(t: ^testing.T) {
    state := Scene_Test_State{}
    definition := make_definition()
    stack := scene_stack.new(scene_stack.Context{data = &state}, scene_stack.default_transition(0))
    defer scene_stack.destroy(&stack)
    testing.expect(t, scene_stack.request_push(&stack, &definition))
    scene_stack.update(&stack, 0)
    scene_stack.update(&stack, 0)
    testing.expect(t, scene_stack.request_push(&stack, &definition))
    scene_stack.update(&stack, 0)
    scene_stack.update(&stack, 0)
    testing.expect(t, state.suspends == 1 && scene_stack.depth(&stack) == 2)
    testing.expect(t, scene_stack.request_pop(&stack))
    scene_stack.update(&stack, 0)
    scene_stack.update(&stack, 0)
    testing.expect(t, state.exits == 1 && state.resumes == 1 && scene_stack.depth(&stack) == 1)
}

@(test)
scene_stack_exposes_transition_progress_until_commit_and_settle :: proc(t: ^testing.T) {
    state := Scene_Test_State{}
    definition := make_definition()
    stack := scene_stack.new(scene_stack.Context{data = &state}, scene_stack.default_transition(1))
    defer scene_stack.destroy(&stack)

    testing.expect(t, scene_stack.request_push(&stack, &definition))
    scene_stack.update(&stack, 0)
    testing.expect(t, scene_stack.depth(&stack) == 0 && scene_stack.transition_progress(&stack) == 0)
    scene_stack.update(&stack, .5)
    testing.expect(t, scene_stack.depth(&stack) == 0 && scene_stack.transition_progress(&stack) == .5)
    scene_stack.update(&stack, .5)
    testing.expect(t, scene_stack.depth(&stack) == 1 && state.enters == 1)
    scene_stack.update(&stack, .5)
    testing.expect(t, scene_stack.transition_progress(&stack) == .5)
    scene_stack.update(&stack, .5)
    testing.expect(t, !scene_stack.is_busy(&stack))
}
