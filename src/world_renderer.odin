package main

import atmosphere "../packages/atmosphere"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math"
import "core:mem"
import vk "vendor:vulkan"
import rl "zelda_engine:canvas2d"
import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"

WORLD_VERTEX_CAPACITY :: 32_000
CLIPMAP_GRID_RESOLUTION :: (terrain.RING_RESOLUTION - 1) / 2 + 2
CLIPMAP_VERTEX_COUNT :: CLIPMAP_GRID_RESOLUTION * CLIPMAP_GRID_RESOLUTION
CLIPMAP_FULL_INDEX_COUNT :: (CLIPMAP_GRID_RESOLUTION - 1) * (CLIPMAP_GRID_RESOLUTION - 1) * 6

World_Vertex :: struct {
	position: [3]f32,
	color:    [4]f32,
	kind:     f32,
}

World_Push :: struct {
	camera_position: [4]f32,
	camera_right:    [4]f32,
	camera_up:       [4]f32,
	camera_forward:  [4]f32,
	projection:      [4]f32,
	fog_color:       [4]f32,
	water:           [4]f32,
	sun:             [4]f32,
}

Sky_Push :: struct {
	camera_right:   [4]f32,
	camera_up:      [4]f32,
	camera_forward: [4]f32,
	sun_direction:  [4]f32,
	time_light:     [4]f32,
	wind_cloud:     [4]f32,
	haze_severity:  [4]f32,
}

World_Renderer :: struct {
	editor:               ^Editor,
	ctx:                  ^engine.Vk_Context,
	pipelines:            [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
	sky_pipelines:        [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
	layout:               vk.PipelineLayout,
	sky_layout:           vk.PipelineLayout,
	vertex:               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	vertices:             [dynamic]World_Vertex,
	clipmap_vertex:       [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]engine.Vk_Buffer,
	clipmap_index:        engine.Vk_Buffer,
	clipmap_full_indices: u32,
	clipmap_ring_first:   u32,
	clipmap_ring_indices: u32,
	clipmap_revision:     [engine.MAX_FRAMES_IN_FLIGHT]u64,
	clipmap_center:       [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS][2]f32,
	clipmap_valid:        [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]bool,
	initialized:          bool,
}

world_renderer: World_Renderer

#assert(size_of(World_Push) == 128)
#assert(size_of(Sky_Push) == 112)
#assert(offset_of(Sky_Push, sun_direction) == 48)
#assert(offset_of(Sky_Push, time_light) == 64)
#assert(offset_of(Sky_Push, wind_cloud) == 80)
#assert(offset_of(Sky_Push, haze_severity) == 96)

world_color :: proc(color: rl.Color) -> [4]f32 {
	return {f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
}

world_sky_horizon_color :: proc(sky: atmosphere.Sky_State) -> rl.Color {
	horizon := rl.Color{184, 209, 209, 255}
	storm := clamp(sky.weather.severity * .68 + sky.weather.precipitation * .52, 0, 1)
	storm_horizon := color_lerp({92, 110, 117, 255}, {112, 125, 128, 255}, sky.weather.haze * .55)
	horizon = color_lerp(horizon, storm_horizon, storm * .82)
	horizon = color_lerp({24, 40, 59, 255}, horizon, sky.daylight)
	return {
		u8(clamp(f32(horizon.r) + 255 * .34 * sky.twilight, 0, 255)),
		u8(clamp(f32(horizon.g) + 255 * .16 * sky.twilight, 0, 255)),
		u8(clamp(f32(horizon.b) + 255 * .08 * sky.twilight, 0, 255)),
		255,
	}
}

world_vertex :: proc(point: third_person.Vec3, color: rl.Color) -> World_Vertex {
	return {{point.x, point.y, point.z}, world_color(color), 0}
}

world_water_vertex :: proc(point: third_person.Vec3, color: rl.Color) -> World_Vertex {
	return {{point.x, point.y, point.z}, world_color(color), 1}
}

world_triangle :: proc(a, b, c: third_person.Vec3, color: rl.Color) {
	if len(world_renderer.vertices) + 3 > WORLD_VERTEX_CAPACITY do return
	append(
		&world_renderer.vertices,
		world_vertex(a, color),
		world_vertex(b, color),
		world_vertex(c, color),
	)
}

world_triangle_colored :: proc(a, b, c: third_person.Vec3, color_a, color_b, color_c: rl.Color) {
	if len(world_renderer.vertices) + 3 > WORLD_VERTEX_CAPACITY do return
	append(
		&world_renderer.vertices,
		world_vertex(a, color_a),
		world_vertex(b, color_b),
		world_vertex(c, color_c),
	)
}

world_quad :: proc(a, b, c, d: third_person.Vec3, color: rl.Color) {
	world_triangle(a, b, c, color)
	world_triangle(a, c, d, color)
}

world_quad_colored :: proc(
	a, b, c, d: third_person.Vec3,
	color_a, color_b, color_c, color_d: rl.Color,
) {
	world_triangle_colored(a, b, c, color_a, color_b, color_c)
	world_triangle_colored(a, c, d, color_a, color_c, color_d)
}

world_water_quad :: proc(a, b, c, d: third_person.Vec3, color: rl.Color) {
	if len(world_renderer.vertices) + 6 > WORLD_VERTEX_CAPACITY do return
	append(
		&world_renderer.vertices,
		world_water_vertex(a, color),
		world_water_vertex(b, color),
		world_water_vertex(c, color),
		world_water_vertex(a, color),
		world_water_vertex(c, color),
		world_water_vertex(d, color),
	)
}

world_ocean :: proc(editor: ^Editor) {
	camera := perspective_camera(
		editor.camera_pose,
		editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
	)
	extent := editor.in_map ? f32(3000) : f32(15000)
	divisions := 32
	cell := extent * 2 / f32(divisions)
	// A snapped tiled field surrounds the camera in every direction. Unlike the
	// former forward slab, it has no near edge for a high, downward-looking
	// camera to expose at the bottom of the viewport.
	center_x := f32(math.floor(f64(camera.position.x / cell))) * cell
	center_z := f32(math.floor(f64(camera.position.z / cell))) * cell
	ocean_y := editor.project.sea_level - (editor.in_map ? f32(.08) : f32(2))
	color := rl.Color{48, 112, 142, 255}
	for z_index in 0 ..< divisions {
		z0 := center_z - extent + f32(z_index) * cell
		z1 := z0 + cell
		for x_index in 0 ..< divisions {
			x0 := center_x - extent + f32(x_index) * cell
			x1 := x0 + cell
			world_water_quad(
				{x0, ocean_y, z0},
				{x1, ocean_y, z0},
				{x1, ocean_y, z1},
				{x0, ocean_y, z1},
				color,
			)
		}
	}
}

world_box :: proc(center, size: third_person.Vec3, color: rl.Color) {
	x, y, z := size.x * .5, size.y * .5, size.z * .5
	p := [8]third_person.Vec3 {
		{center.x - x, center.y - y, center.z - z},
		{center.x + x, center.y - y, center.z - z},
		{center.x + x, center.y + y, center.z - z},
		{center.x - x, center.y + y, center.z - z},
		{center.x - x, center.y - y, center.z + z},
		{center.x + x, center.y - y, center.z + z},
		{center.x + x, center.y + y, center.z + z},
		{center.x - x, center.y + y, center.z + z},
	}
	world_quad(p[0], p[3], p[2], p[1], color)
	world_quad(p[4], p[5], p[6], p[7], color)
	world_quad(p[0], p[4], p[7], p[3], color)
	world_quad(p[1], p[2], p[6], p[5], color)
	world_quad(p[3], p[7], p[6], p[2], color)
	world_quad(p[0], p[1], p[5], p[4], color)
}

clipmap_vertex_color :: proc(editor: ^Editor, level: int, x, z, height: f32) -> rl.Color {
	cell := editor.project.levels[level].cell_size
	left := terrain.sample_height(&editor.project, level, x - cell, z)
	right := terrain.sample_height(&editor.project, level, x + cell, z)
	back := terrain.sample_height(&editor.project, level, x, z - cell)
	front := terrain.sample_height(&editor.project, level, x, z + cell)
	normal := vec_normalize(
		vec_cross({y = front - back, z = cell * 2}, {x = cell * 2, y = right - left}),
	)
	light := vec_normalize(third_person.Vec3{x = -.45, y = .85, z = -.3})
	shade := clamp(.48 + max(vec_dot(normal, light), 0) * .52, .42, 1.05)
	base := terrain_color(
		max(height, editor.project.sea_level + .12),
		terrain.sample_material(&editor.project, level, x, z),
		editor.project.sea_level,
	)
	return {
		u8(clamp(f32(base.r) * shade, 0, 255)),
		u8(clamp(f32(base.g) * shade, 0, 255)),
		u8(clamp(f32(base.b) * shade, 0, 255)),
		255,
	}
}

clipmap_update_level :: proc(editor: ^Editor, frame_index, level: int, center: [2]f32) {
	buffer := &world_renderer.clipmap_vertex[frame_index][level]
	vertices := cast([^]World_Vertex)buffer.mapped
	data := &editor.project.levels[level]
	grid_cell := data.cell_size * 2
	half_grid := f32(CLIPMAP_GRID_RESOLUTION - 1) * .5
	for z in 0 ..< CLIPMAP_GRID_RESOLUTION {
		world_z := center[1] + (f32(z) - half_grid) * grid_cell
		for x in 0 ..< CLIPMAP_GRID_RESOLUTION {
			world_x := center[0] + (f32(x) - half_grid) * grid_cell
			height := terrain.sample_height(&editor.project, level, world_x, world_z)
			vertex := world_vertex(
				{world_x, height, world_z},
				clipmap_vertex_color(editor, level, world_x, world_z, height),
			)
			vertex.kind = 2
			vertices[z * CLIPMAP_GRID_RESOLUTION + x] = vertex
		}
	}
}

clipmap_update :: proc(editor: ^Editor, frame_index: int) {
	camera := perspective_camera(
		editor.camera_pose,
		editor.in_map && editor.pilot.mode == .Driving ? editor.flight_camera.focal_length : 1.35,
	)
	revision_changed := world_renderer.clipmap_revision[frame_index] != editor.project.revision
	snap := editor.project.levels[0].cell_size * 2
	center := [2]f32 {
		f32(math.round(f64(camera.position.x / snap))) * snap,
		f32(math.round(f64(camera.position.z / snap))) * snap,
	}
	for level in 0 ..< terrain.CLIPMAP_LEVELS {
		if revision_changed ||
		   !world_renderer.clipmap_valid[frame_index][level] ||
		   world_renderer.clipmap_center[frame_index][level] != center {
			clipmap_update_level(editor, frame_index, level, center)
			world_renderer.clipmap_center[frame_index][level] = center
			world_renderer.clipmap_valid[frame_index][level] = true
		}
	}
	world_renderer.clipmap_revision[frame_index] = editor.project.revision
}

clipmap_append_cell :: proc(indices: ^[dynamic]u32, x, z: int) {
	row := CLIPMAP_GRID_RESOLUTION
	a := u32(z * row + x)
	b := u32(z * row + x + 1)
	c := u32((z + 1) * row + x + 1)
	d := u32((z + 1) * row + x)
	append(indices, a, b, c, a, c, d)
}

clipmap_create_indices :: proc(ctx: ^engine.Vk_Context) -> bool {
	indices := make([dynamic]u32, 0, CLIPMAP_FULL_INDEX_COUNT * 2)
	defer delete(indices)
	for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
		for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
			clipmap_append_cell(&indices, x, z)
		}
	}
	world_renderer.clipmap_full_indices = u32(len(indices))
	world_renderer.clipmap_ring_first = u32(len(indices))
	hole_min := CLIPMAP_GRID_RESOLUTION / 4
	hole_max := CLIPMAP_GRID_RESOLUTION - hole_min - 1
	for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
		for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
			if x >= hole_min && x < hole_max && z >= hole_min && z < hole_max do continue
			clipmap_append_cell(&indices, x, z)
		}
	}
	world_renderer.clipmap_ring_indices = u32(len(indices)) - world_renderer.clipmap_ring_first
	if !engine.vk_create_host_buffer(
		ctx,
		vk.DeviceSize(len(indices) * size_of(u32)),
		{.INDEX_BUFFER},
		&world_renderer.clipmap_index,
	) {
		return false
	}
	mem.copy_non_overlapping(
		world_renderer.clipmap_index.mapped,
		raw_data(indices[:]),
		len(indices) * size_of(u32),
	)
	return true
}

world_infrastructure :: proc(editor: ^Editor) {
	half := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[0].cell_size * .5
	for sign in terrain.DEFAULT_ISLAND_SIGNS {
		x, z :=
			sign *
			half *
			terrain.DEFAULT_ISLAND_OFFSET,
			sign *
			half *
			terrain.DEFAULT_ISLAND_OFFSET
		run_l, run_w :=
			half * terrain.DEFAULT_RUNWAY_HALF_LENGTH, half * terrain.DEFAULT_RUNWAY_HALF_WIDTH
		y := terrain.sample_height(&editor.project, 0, x, z) + .05
		world_box({x, y, z}, {run_l * 2, .08, run_w * 2}, {60, 66, 67, 255})
		for marker in -3 ..= 3 {
			mx := x + f32(marker) * run_l * .22
			world_box({mx, y + .06, z}, {run_l * .11, .025, .12}, {238, 232, 186, 255})
		}
		// Run straight out from the island's outer shoreline. The former
		// diagonal endpoints crossed the coast at different Z coordinates,
		// which made the deck read as a detached triangular wedge.
		ix := x + sign * half * terrain.DEFAULT_ISLAND_RADIUS * .62
		ox := x + sign * half * terrain.DEFAULT_ISLAND_RADIUS * 1.18
		iz, oz := z, z
		// Keep the deck level from land to water. Sloping it down to sea level
		// buried most of the mesh inside the island and left only its far tip.
		deck_height := f32(terrain.DEFAULT_ISLAND_HEIGHT + .24)
		iy, oy := deck_height, deck_height
		w := half * .018
		world_quad(
			{ix, iy, iz - w},
			{ox, oy, oz - w},
			{ox, oy, oz + w},
			{ix, iy, iz + w},
			{137, 89, 48, 255},
		)
	}
}

world_aircraft :: proc(editor: ^Editor) {
	mesh := vehicles.postale_mesh()
	vehicles.animate_postale_mesh(
		&mesh,
		editor.postale.flap_fraction,
		editor.flight_control.pitch,
		editor.flight_control.roll,
		editor.flight_control.yaw,
		editor.postale.propeller_turns,
	)
	for triangle in vehicles.mesh_triangles(&mesh) {
		a := mesh.vertices[triangle.a]
		b := mesh.vertices[triangle.b]
		c := mesh.vertices[triangle.c]
		world_triangle(
			postale_vertex_world(&editor.postale, a.position, .68),
			postale_vertex_world(&editor.postale, b.position, .68),
			postale_vertex_world(&editor.postale, c.position, .68),
			aircraft_part_color(a.part),
		)
	}
}

car_vertex_world :: proc(editor: ^Editor, position: [3]f32) -> third_person.Vec3 {
	origin := editor.car.position
	// The authored car faces local -Z. Apply restrained pitch and roll feedback
	// before rotating that axis onto the simulation's ground-plane heading.
	right, up, forward := position[0], position[1], -position[2]
	pitch_cos, pitch_sin :=
		math.cos(editor.car_drive.body_pitch), math.sin(editor.car_drive.body_pitch)
	forward, up = forward * pitch_cos - up * pitch_sin, forward * pitch_sin + up * pitch_cos
	roll_cos, roll_sin :=
		math.cos(editor.car_drive.body_roll), math.sin(editor.car_drive.body_roll)
	right, up = right * roll_cos - up * roll_sin, right * roll_sin + up * roll_cos
	heading_cos, heading_sin := math.cos(editor.car.yaw_radians), math.sin(editor.car.yaw_radians)
	return {
		x = origin.x + forward * heading_cos - right * heading_sin,
		y = origin.y + up,
		z = origin.z + forward * heading_sin + right * heading_cos,
	}
}

world_car :: proc(editor: ^Editor) {
	origin := editor.car.position
	mesh := vehicles.simple_car_mesh()
	for triangle in vehicles.mesh_triangles(&mesh) {
		a := mesh.vertices[triangle.a]
		b := mesh.vertices[triangle.b]
		c := mesh.vertices[triangle.c]
		world_triangle(
			car_vertex_world(editor, a.position),
			car_vertex_world(editor, b.position),
			car_vertex_world(editor, c.position),
			aircraft_part_color(a.part),
		)
	}
}

world_character :: proc(editor: ^Editor) {
	if !editor.in_map || editor.pilot.mode != .On_Foot do return
	p := editor.player.position
	world_box({p.x, p.y + .72, p.z}, {.42, 1.15, .28}, {42, 213, 201, 255})
	world_box({p.x, p.y + 1.48, p.z}, {.34, .34, .34}, {247, 221, 167, 255})
	forward := third_person.Vec3 {
		x = -math.sin(editor.player.facing_yaw_radians),
		z = -math.cos(editor.player.facing_yaw_radians),
	}
	world_box(
		{p.x + forward.x * .25, p.y + 1.16, p.z + forward.z * .25},
		{.16, .16, .55},
		{247, 221, 167, 255},
	)
}

world_brush :: proc(editor: ^Editor) {
	if editor.in_map do return
	camera := perspective_camera(
		editor.camera_pose,
		editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
	)
	mouse, inside := rl.GetWorldMousePosition()
	if !inside do return
	x, z, hit := terrain_under_cursor_3d(
		editor,
		camera,
		mouse,
		ADRIATIC_WORLD_WIDTH,
		ADRIATIC_WORLD_HEIGHT,
	)
	if !hit do return
	segments := 48
	color := rl.Color{230, 244, 218, 230}
	for i in 0 ..< segments {
		a0 := f32(i) * 2 * math.PI / f32(segments)
		a1 := f32(i + 1) * 2 * math.PI / f32(segments)
		p0 := third_person.Vec3 {
			x = x + math.cos(a0) * editor.radius,
			z = z + math.sin(a0) * editor.radius,
		}
		p1 := third_person.Vec3 {
			x = x + math.cos(a1) * editor.radius,
			z = z + math.sin(a1) * editor.radius,
		}
		p0.y = terrain.sample_height(&editor.project, 0, p0.x, p0.z) + .10
		p1.y = terrain.sample_height(&editor.project, 0, p1.x, p1.z) + .10
		center := third_person.Vec3 {
			x = x,
			y = terrain.sample_height(&editor.project, 0, x, z) + .09,
			z = z,
		}
		world_triangle(center, p0, p1, color)
	}
}

world_build :: proc(editor: ^Editor) {
	clear(&world_renderer.vertices)
	// Depth testing makes submission order independent. Put authored gameplay
	// meshes first so dense terrain can consume only the remaining capacity
	// instead of silently dropping vehicles at the end of the frame.
	world_ocean(editor)
	world_infrastructure(editor)
	world_aircraft(editor)
	world_car(editor)
	world_character(editor)
	world_brush(editor)
}

world_renderer_create :: proc(ctx: ^engine.Vk_Context) -> bool {
	pr := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		size       = u32(size_of(World_Push)),
	}
	li := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pr,
	}
	if vk.CreatePipelineLayout(ctx.device, &li, nil, &world_renderer.layout) != .SUCCESS do return false
	sky_pr := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		size       = u32(size_of(Sky_Push)),
	}
	sky_li := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &sky_pr,
	}
	if vk.CreatePipelineLayout(ctx.device, &sky_li, nil, &world_renderer.sky_layout) != .SUCCESS do return false
	vert, frag: engine.Vk_Shader_Module
	if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/world.slang", "shaders/world.vert", .Vertex, "vertex_main", &vert) do return false
	defer engine.vk_destroy_shader_module(ctx, &vert)
	if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/world.slang", "shaders/world.frag", .Fragment, "fragment_main", &frag) do return false
	defer engine.vk_destroy_shader_module(ctx, &frag)
	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert.handle,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag.handle,
			pName = "main",
		},
	}
	binding := vk.VertexInputBindingDescription {
		stride    = u32(size_of(World_Vertex)),
		inputRate = .VERTEX,
	}
	attrs := [3]vk.VertexInputAttributeDescription {
		{
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(World_Vertex, position)),
		},
		{
			location = 1,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(World_Vertex, color)),
		},
		{location = 2, format = .R32_SFLOAT, offset = u32(offset_of(World_Vertex, kind))},
	}
	vi := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding,
		vertexAttributeDescriptionCount = 3,
		pVertexAttributeDescriptions    = raw_data(attrs[:]),
	}
	ia := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}
	vp := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}
	rs := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = {},
		frontFace   = .COUNTER_CLOCKWISE,
		lineWidth   = 1,
	}
	ms := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}
	depth := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS,
	}
	ca := vk.PipelineColorBlendAttachmentState {
		blendEnable    = false,
		colorWriteMask = {.R, .G, .B, .A},
	}
	cb := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &ca,
	}
	ds := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	di := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(ds[:]),
	}
	info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = raw_data(stages[:]),
		pVertexInputState   = &vi,
		pInputAssemblyState = &ia,
		pViewportState      = &vp,
		pRasterizationState = &rs,
		pMultisampleState   = &ms,
		pDepthStencilState  = &depth,
		pColorBlendState    = &cb,
		pDynamicState       = &di,
		layout              = world_renderer.layout,
	}
	if !render3d.create_color_pipeline_variants(ctx, &info, .D32_SFLOAT, &world_renderer.pipelines) do return false
	sky_vert, sky_frag: engine.Vk_Shader_Module
	if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/sky.slang", "shaders/world-sky.vert", .Vertex, "sky_vertex", &sky_vert) do return false
	defer engine.vk_destroy_shader_module(ctx, &sky_vert)
	if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/sky.slang", "shaders/world-sky.frag", .Fragment, "sky_fragment", &sky_frag) do return false
	defer engine.vk_destroy_shader_module(ctx, &sky_frag)
	stages[0].module = sky_vert.handle
	stages[1].module = sky_frag.handle
	sky_vi := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}
	sky_depth := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = false,
		depthWriteEnable = false,
	}
	info.pVertexInputState = &sky_vi
	info.pDepthStencilState = &sky_depth
	info.layout = world_renderer.sky_layout
	if !render3d.create_color_pipeline_variants(ctx, &info, .D32_SFLOAT, &world_renderer.sky_pipelines) do return false
	for &buffer in world_renderer.vertex {
		if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(WORLD_VERTEX_CAPACITY * size_of(World_Vertex)), {.VERTEX_BUFFER}, &buffer) do return false
	}
	for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
		for level in 0 ..< terrain.CLIPMAP_LEVELS {
			if !engine.vk_create_host_buffer(
				ctx,
				vk.DeviceSize(CLIPMAP_VERTEX_COUNT * size_of(World_Vertex)),
				{.VERTEX_BUFFER},
				&world_renderer.clipmap_vertex[frame][level],
			) {
				return false
			}
		}
	}
	if !clipmap_create_indices(ctx) do return false
	world_renderer.vertices = make([dynamic]World_Vertex, 0, WORLD_VERTEX_CAPACITY)
	world_renderer.ctx = ctx
	world_renderer.initialized = true
	return true
}

world_pass :: proc(pass: ^rl.World_Pass_Context, _: rawptr) {
	if !world_renderer.initialized && !world_renderer_create(pass.ctx) do return
	editor := world_renderer.editor
	if editor == nil do return
	world_build(editor)
	clipmap_update(editor, int(pass.frame.frame_index))
	buffer := &world_renderer.vertex[pass.frame.frame_index]
	if len(world_renderer.vertices) > 0 {
		mem.copy_non_overlapping(
			buffer.mapped,
			raw_data(world_renderer.vertices[:]),
			len(world_renderer.vertices) * size_of(World_Vertex),
		)
	}
	viewport := vk.Viewport {
		width    = f32(pass.framebuffer_extent.width),
		height   = f32(pass.framebuffer_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}
	scissor := vk.Rect2D {
		extent = pass.framebuffer_extent,
	}
	vk.CmdSetViewport(pass.frame.command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(pass.frame.command_buffer, 0, 1, &scissor)
	pipeline_index := pass.color_format == vk.Format.R16G16B16A16_SFLOAT ? 1 : 0
	camera := perspective_camera(
		editor.camera_pose,
		editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
	)
	sky := atmosphere.sample(&editor.atmosphere)
	fog := world_sky_horizon_color(sky)
	world_push := World_Push {
		camera_position = {
			camera.position.x,
			camera.position.y,
			camera.position.z,
			editor.in_map ? f32(.08) : f32(100),
		},
		camera_right    = {
			camera.right.x,
			camera.right.y,
			camera.right.z,
			editor.in_map ? f32(800) : f32(10000),
		},
		camera_up       = {camera.up.x, camera.up.y, camera.up.z, 0},
		camera_forward  = {camera.forward.x, camera.forward.y, camera.forward.z, 0},
		projection      = {
			camera.focal_length,
			f32(pass.framebuffer_extent.width) / f32(max(pass.framebuffer_extent.height, 1)),
			f32(terrain.WORLD_SIZE_METERS * .55),
			f32(terrain.WORLD_SIZE_METERS * 1.5),
		},
		fog_color       = world_color(fog),
		water           = {
			sky.cloud_time_seconds,
			sky.weather.severity,
			sky.weather.wind[0],
			sky.weather.wind[1],
		},
		sun             = {
			sky.sun_direction[0],
			sky.sun_direction[1],
			sky.sun_direction[2],
			sky.daylight,
		},
	}
	sky_push := Sky_Push {
		camera_right   = {
			camera.right.x,
			camera.right.y,
			camera.right.z,
			f32(pass.framebuffer_extent.width) / f32(max(pass.framebuffer_extent.height, 1)),
		},
		camera_up      = {camera.up.x, camera.up.y, camera.up.z, camera.focal_length},
		camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, 0},
		sun_direction  = {
			sky.sun_direction[0],
			sky.sun_direction[1],
			sky.sun_direction[2],
			f32(sky.cloud_seed),
		},
		time_light     = {sky.world_minutes, sky.cloud_time_seconds, sky.daylight, sky.twilight},
		wind_cloud     = {
			sky.weather.wind[0],
			sky.weather.wind[1],
			sky.weather.cloud_cover,
			sky.weather.precipitation,
		},
		haze_severity  = {sky.weather.haze, sky.weather.severity, 0, 0},
	}
	vk.CmdPushConstants(
		pass.frame.command_buffer,
		world_renderer.sky_layout,
		{.VERTEX, .FRAGMENT},
		0,
		u32(size_of(sky_push)),
		&sky_push,
	)
	vk.CmdBindPipeline(
		pass.frame.command_buffer,
		.GRAPHICS,
		world_renderer.sky_pipelines[pipeline_index],
	)
	vk.CmdDraw(pass.frame.command_buffer, 3, 1, 0, 0)
	vk.CmdBindPipeline(
		pass.frame.command_buffer,
		.GRAPHICS,
		world_renderer.pipelines[pipeline_index],
	)
	vk.CmdPushConstants(
		pass.frame.command_buffer,
		world_renderer.layout,
		{.VERTEX, .FRAGMENT},
		0,
		u32(size_of(world_push)),
		&world_push,
	)
	offset := vk.DeviceSize(0)
	if len(world_renderer.vertices) > 0 {
		vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 1, &buffer.handle, &offset)
		vk.CmdDraw(pass.frame.command_buffer, u32(len(world_renderer.vertices)), 1, 0, 0)
	}
	vk.CmdBindIndexBuffer(
		pass.frame.command_buffer,
		world_renderer.clipmap_index.handle,
		0,
		.UINT32,
	)
	for level in 0 ..< terrain.CLIPMAP_LEVELS {
		level_buffer := &world_renderer.clipmap_vertex[pass.frame.frame_index][level]
		vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 1, &level_buffer.handle, &offset)
		if level == 0 {
			vk.CmdDrawIndexed(
				pass.frame.command_buffer,
				world_renderer.clipmap_full_indices,
				1,
				0,
				0,
				0,
			)
		} else {
			vk.CmdDrawIndexed(
				pass.frame.command_buffer,
				world_renderer.clipmap_ring_indices,
				1,
				world_renderer.clipmap_ring_first,
				0,
				0,
			)
		}
	}
}

world_renderer_attach :: proc(editor: ^Editor) {
	world_renderer.editor = editor
	rl.SetWorldPass(world_pass)
}

world_renderer_destroy :: proc() {
	if !world_renderer.initialized do return
	_ = vk.DeviceWaitIdle(world_renderer.ctx.device)
	for &buffer in world_renderer.vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
	for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
		for level in 0 ..< terrain.CLIPMAP_LEVELS {
			engine.vk_destroy_buffer(
				world_renderer.ctx,
				&world_renderer.clipmap_vertex[frame][level],
			)
		}
	}
	engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_index)
	render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.pipelines)
	render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.sky_pipelines)
	if world_renderer.layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.layout, nil)
	if world_renderer.sky_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.sky_layout, nil)
	delete(world_renderer.vertices)
	world_renderer = {}
}
