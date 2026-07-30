package main

import im "../packages/imgui"
import imgui_vk "../packages/imgui/impl_vulkan"
import "core:c"
import "core:fmt"
import "core:math"
import vk "vendor:vulkan"
import rl "zelda_engine:canvas2d"
import engine "zelda_engine:engine"

IMGUI_DESCRIPTOR_COUNT :: 1000

Imgui_State :: struct {
    ctx:             ^im.Context,
    io:              ^im.IO,
    device:          vk.Device,
    descriptor_pool: vk.DescriptorPool,
    color_format:    vk.Format,
    last_time:       f64,
    text_input_active: bool,
    show_demo:       bool,
    initialized:     bool,
}

imgui: Imgui_State

imgui_srgb_channel_to_linear :: proc(channel: f32) -> f32 {
    if channel <= 0.04045 do return channel / 12.92
    return math.pow((channel + 0.055) / 1.055, 2.4)
}

imgui_linearize_style_colors :: proc() {
    style := im.GetStyle()
    if style == nil do return
    for &color in style.Colors {
        color.x = imgui_srgb_channel_to_linear(color.x)
        color.y = imgui_srgb_channel_to_linear(color.y)
        color.z = imgui_srgb_channel_to_linear(color.z)
    }
}

imgui_vk_loader :: proc "c" (name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
    ctx := cast(^engine.Vk_Context)user_data
    if ctx == nil || ctx.instance == nil do return nil
    return vk.GetInstanceProcAddr(ctx.instance, name)
}

imgui_create_descriptor_pool :: proc(ctx: ^engine.Vk_Context) -> vk.DescriptorPool {
    pools := [1]vk.DescriptorPoolSize{{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = IMGUI_DESCRIPTOR_COUNT}}
    info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        flags         = {.FREE_DESCRIPTOR_SET},
        maxSets       = IMGUI_DESCRIPTOR_COUNT,
        poolSizeCount = u32(len(pools)),
        pPoolSizes    = &pools[0],
    }
    pool: vk.DescriptorPool
    if vk.CreateDescriptorPool(ctx.device, &info, nil, &pool) != .SUCCESS do return {}
    engine.vk_set_debug_name(ctx, .DESCRIPTOR_POOL, auto_cast pool, "ImGui descriptor pool")
    return pool
}

imgui_init :: proc(pass: ^rl.Ui_Pass_Context) -> bool {
    if imgui.initialized do return true
    imgui.ctx = im.CreateContext()
    if imgui.ctx == nil do return false
    im.SetCurrentContext(imgui.ctx)
    im.CHECKVERSION()
    imgui.io = im.GetIO()
    imgui.io.ConfigFlags += {.NavEnableKeyboard, .IsSRGB}
    imgui.io.BackendRendererName = "imgui_impl_vulkan"
    im.StyleColorsDark()
    // The stock Vulkan backend forwards packed vertex colors unchanged. Store
    // the style palette in linear light so the sRGB attachment encodes it once.
    imgui_linearize_style_colors()

    imgui.descriptor_pool = imgui_create_descriptor_pool(pass.ctx)
    if imgui.descriptor_pool == vk.DescriptorPool(0) {
        im.DestroyContext(imgui.ctx)
        imgui = {}
        return false
    }

    imgui.color_format = pass.color_format
    imgui.device = pass.ctx.device
    if !imgui_vk.LoadFunctions(pass.ctx.caps.api_version, imgui_vk_loader, cast(rawptr)pass.ctx) {
        vk.DestroyDescriptorPool(pass.ctx.device, imgui.descriptor_pool, nil)
        im.DestroyContext(imgui.ctx)
        imgui = {}
        return false
    }
    rendering := engine.vk_pipeline_rendering_info(&imgui.color_format)
    init_info := imgui_vk.InitInfo {
        ApiVersion                  = pass.ctx.caps.api_version,
        Instance                    = pass.ctx.instance,
        PhysicalDevice              = pass.ctx.physical_device,
        Device                      = pass.ctx.device,
        QueueFamily                 = u32(pass.ctx.caps.queue_families.graphics),
        Queue                       = pass.ctx.graphics_queue,
        DescriptorPool              = imgui.descriptor_pool,
        MinImageCount               = max(pass.ctx.swapchain_image_count, u32(2)),
        ImageCount                  = pass.ctx.swapchain_image_count,
        MSAASamples                 = ._1,
        UseDynamicRendering         = true,
        PipelineRenderingCreateInfo = rendering,
    }
    if !imgui_vk.Init(&init_info) {
        vk.DestroyDescriptorPool(pass.ctx.device, imgui.descriptor_pool, nil)
        im.DestroyContext(imgui.ctx)
        imgui = {}
        return false
    }
    if !imgui_vk.CreateFontsTexture() {
        imgui_vk.Shutdown()
        vk.DestroyDescriptorPool(pass.ctx.device, imgui.descriptor_pool, nil)
        im.DestroyContext(imgui.ctx)
        imgui = {}
        return false
    }
    imgui.show_demo = false
    imgui.last_time = rl.GetTime()
    imgui.initialized = true
    return true
}

@(no_instrumentation)
imgui_add_key :: #force_inline proc(key: im.Key, canvas_key: rl.KeyboardKey) {
    im.IO_AddKeyEvent(imgui.io, key, rl.IsKeyDown(canvas_key))
}

imgui_begin_frame :: proc(pass: ^rl.Ui_Pass_Context) -> bool {
    if !imgui_init(pass) do return false

    now := rl.GetTime()
    delta := now - imgui.last_time
    imgui.last_time = now
    imgui.io.DeltaTime = clamp(f32(delta), f32(1.0 / 240.0), f32(1.0 / 15.0))
    imgui.io.DisplaySize = {f32(pass.logical_extent[0]), f32(pass.logical_extent[1])}
    imgui.io.DisplayFramebufferScale = {
        f32(pass.framebuffer_extent.width) / f32(max(pass.logical_extent[0], 1)),
        f32(pass.framebuffer_extent.height) / f32(max(pass.logical_extent[1], 1)),
    }

    mouse := rl.GetMousePosition()
    im.IO_AddMousePosEvent(imgui.io, mouse.x, mouse.y)
    im.IO_AddMouseButtonEvent(imgui.io, c.int(0), rl.IsMouseButtonDown(.LEFT))
    im.IO_AddMouseButtonEvent(imgui.io, c.int(1), rl.IsMouseButtonDown(.RIGHT))
    im.IO_AddMouseButtonEvent(imgui.io, c.int(2), rl.IsMouseButtonDown(.MIDDLE))
    im.IO_AddMouseWheelEvent(imgui.io, 0, rl.GetMouseWheelMove())

    imgui_add_key(.Tab, .TAB)
    imgui_add_key(.LeftArrow, .LEFT)
    imgui_add_key(.RightArrow, .RIGHT)
    imgui_add_key(.UpArrow, .UP)
    imgui_add_key(.DownArrow, .DOWN)
    imgui_add_key(.Enter, .ENTER)
    imgui_add_key(.Escape, .ESCAPE)
    imgui_add_key(.Backspace, .BACKSPACE)
    imgui_add_key(.Space, .SPACE)
    imgui_add_key(.LeftShift, .LEFT_SHIFT)
    imgui_add_key(.RightShift, .RIGHT_SHIFT)
    imgui_add_key(.A, .A)
    imgui_add_key(.C, .C)
    imgui_add_key(.D, .D)
    imgui_add_key(.E, .E)
    imgui_add_key(.Q, .Q)
    imgui_add_key(.R, .R)
    imgui_add_key(.S, .S)
    imgui_add_key(.W, .W)

    text_input := rl.GetTextInput()
    if len(text_input) > 0 {
        im.IO_AddInputCharactersUTF8(imgui.io, fmt.ctprintf("%s", text_input))
    }
    imgui_vk.NewFrame()
    im.NewFrame()
    return true
}

@(no_instrumentation)
imgui_captures_mouse :: #force_inline proc() -> bool {
    return imgui.initialized && imgui.io != nil && imgui.io.WantCaptureMouse
}

@(no_instrumentation)
imgui_captures_keyboard :: #force_inline proc() -> bool {
    return imgui.initialized && imgui.io != nil && imgui.io.WantCaptureKeyboard
}

imgui_draw :: proc(editor: ^Editor) {
    imgui_draw_tweaks(editor)
    if imgui.show_demo do im.ShowDemoWindow(&imgui.show_demo)
}

imgui_render :: proc(pass: ^rl.Ui_Pass_Context, editor: ^Editor) {
    imgui_draw(editor)
    im.Render()
    imgui_vk.RenderDrawData(im.GetDrawData(), pass.frame.command_buffer)
}

imgui_ui_pass :: proc(pass: ^rl.Ui_Pass_Context, _: rawptr) {
    editor := world_renderer.editor
    wants_text_input := editor != nil && editor.tweak_panel_visible
    if wants_text_input && !imgui.text_input_active {
        imgui.text_input_active = rl.StartTextInput()
    } else if !wants_text_input && imgui.text_input_active {
        _ = rl.StopTextInput()
        imgui.text_input_active = false
    }
    if !imgui_begin_frame(pass) do return
    imgui_render(pass, editor)
}

imgui_destroy :: proc() {
    if !imgui.initialized do return
    if imgui.text_input_active do _ = rl.StopTextInput()
    imgui_vk.Shutdown()
    if imgui.descriptor_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(imgui.device, imgui.descriptor_pool, nil)
    im.DestroyContext(imgui.ctx)
    imgui = {}
}
