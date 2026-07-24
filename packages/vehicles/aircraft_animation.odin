package vehicles

import "core:math"

// Apply these to a freshly constructed model each frame. `propeller_turns` is
// intentionally unbounded so simulation can accumulate it without wrapping.
// Fixed-wing flap input is normalized: 0 retracted, 1 fully deployed.

clamp_unit :: proc(value: f32) -> f32 { if value < 0 do return 0; if value > 1 do return 1; return value }

set_vertical_propeller :: proc(model: ^Aircraft_Wireframe, center_x, center_y, center_z, radius, turns: f32, first, second, third, fourth: int) {
	if model == nil do return
	angle := turns * 6.2831853; c := math.cos(angle)*radius; s := math.sin(angle)*radius
	model.vertices[first].position = {center_x-c, center_y-s, center_z}
	model.vertices[second].position = {center_x+c, center_y+s, center_z}
	model.vertices[third].position = {center_x+s, center_y-c, center_z}
	model.vertices[fourth].position = {center_x-s, center_y+c, center_z}
}

// Postale's broad inboard trailing-edge flaps lower for short-field work;
// its single nose propeller spins in the vertical disk normal to the fuselage.
animate_postale :: proc(model: ^Aircraft_Wireframe, flap_fraction, propeller_turns: f32) {
	if model == nil do return
	flap := clamp_unit(flap_fraction)
	model.vertices[10].position[1] = .9-.62*flap; model.vertices[11].position[1] = .9-.62*flap
	model.vertices[10].position[2] = .65+.28*flap; model.vertices[11].position[2] = .65+.28*flap
	set_vertical_propeller(model, 0, .38, -2.72, .62, propeller_turns, 19, 20, 21, 22)
}

// Pelican carries split trailing-edge flaps for slow water and approach work.
// Each nacelle's short propeller line rotates around its own forward hub.
animate_pelican :: proc(model: ^Aircraft_Wireframe, flap_fraction, propeller_turns: f32) {
	if model == nil do return
	flap := clamp_unit(flap_fraction)
	model.vertices[10].position[1] = 1.05-.54*flap; model.vertices[11].position[1] = 1.05-.54*flap
	model.vertices[10].position[2] = .78+.3*flap; model.vertices[11].position[2] = .78+.3*flap
	angle := propeller_turns*6.2831853; c := math.cos(angle)*.82; s := math.sin(angle)*.82
	model.vertices[12].position = {-3.275-c,.72-s,-.3}; model.vertices[13].position = {-3.275+c,.72+s,-.3}
	model.vertices[14].position = {3.275-c,.72+s,-.3}; model.vertices[15].position = {3.275+c,.72-s,-.3}
}

// Libellula has no wings or flaps: its three lift rotors animate in their
// horizontal disks, with phase offsets that keep the triangular frame readable.
animate_libellula :: proc(model: ^Aircraft_Wireframe, propeller_turns: f32) {
	if model == nil do return
	set_horizontal_rotor(model, -3.2, 1.17, -1, 1.35, propeller_turns, 3, 4)
	set_horizontal_rotor(model, 3.2, 1.17, -1, 1.35, propeller_turns+.333, 5, 6)
	set_horizontal_rotor(model, 0, 1.17, 4.54, 1.35, propeller_turns+.667, 7, 8)
}

set_horizontal_rotor :: proc(model: ^Aircraft_Wireframe, center_x, center_y, center_z, radius, turns: f32, first, second: int) {
	angle := turns*6.2831853; x := math.cos(angle)*radius; z := math.sin(angle)*radius
	model.vertices[first].position = {center_x-x, center_y, center_z-z}
	model.vertices[second].position = {center_x+x, center_y, center_z+z}
}
