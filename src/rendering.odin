package main

import rl "zelda_engine:canvas2d"
import render2d "zelda_engine:render2d"

ADRIATIC_RENDERER_DESCRIPTOR := render2d.Renderer_Descriptor {
	pipeline = {
		vertex = {"assets/shaders/canvas.vert", .Vertex, "main", "shaders/canvas.vert"},
		fragment = {"assets/shaders/canvas.frag", .Fragment, "main", "shaders/canvas.frag"},
		post_vertex = {"assets/shaders/canvas-post.vert", .Vertex, "main", "shaders/canvas-post.vert"},
		post_fragment = {"assets/shaders/canvas-post.frag", .Fragment, "main", "shaders/canvas-post.frag"},
		push_constant_size = size_of(rl.Push),
	},
}
