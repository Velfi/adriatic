package tests

import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:testing"

Car_Mesh_Component :: struct {
	first_triangle, triangle_count: int,
	center:                         [3]f32,
}

car_triangle_winds_outward :: proc(
	t: ^testing.T,
	mesh: ^vehicles.Aircraft_Mesh,
	component: Car_Mesh_Component,
) {
	for index in component.first_triangle ..< component.first_triangle + component.triangle_count {
		triangle := mesh.triangles[index]
		a := mesh.vertices[triangle.a].position
		b := mesh.vertices[triangle.b].position
		c := mesh.vertices[triangle.c].position
		ab := [3]f32{b[0] - a[0], b[1] - a[1], b[2] - a[2]}
		ac := [3]f32{c[0] - a[0], c[1] - a[1], c[2] - a[2]}
		normal := [3]f32 {
			ab[1] * ac[2] - ab[2] * ac[1],
			ab[2] * ac[0] - ab[0] * ac[2],
			ab[0] * ac[1] - ab[1] * ac[0],
		}
		face_center := [3]f32 {
			(a[0] + b[0] + c[0]) / 3,
			(a[1] + b[1] + c[1]) / 3,
			(a[2] + b[2] + c[2]) / 3,
		}
		outward := [3]f32 {
			face_center[0] - component.center[0],
			face_center[1] - component.center[1],
			face_center[2] - component.center[2],
		}
		testing.expect(
			t,
			normal[0] * outward[0] + normal[1] * outward[1] + normal[2] * outward[2] > 0,
		)
	}
}

@(test)
simple_car_has_valid_wireframe_indices :: proc(t: ^testing.T) {
	car := vehicles.simple_car()
	for edge in car.edges {
		testing.expect(t, edge.a >= 0 && edge.a < len(car.vertices))
		testing.expect(t, edge.b >= 0 && edge.b < len(car.vertices))
	}
}

@(test)
simple_car_has_a_raised_cabin_and_wheels :: proc(t: ^testing.T) {
	car := vehicles.simple_car()
	testing.expect(t, car.vertices[12].position[1] > car.vertices[4].position[1])
	testing.expect(t, car.vertices[16].position[1] < car.vertices[0].position[1])
	testing.expect(t, car.vertices[24].position[2] > car.vertices[16].position[2])
}

@(test)
simple_car_solid_mesh_is_closed_and_grouped :: proc(t: ^testing.T) {
	mesh := vehicles.simple_car_mesh()
	testing.expect(t, mesh.vertex_count > 0)
	testing.expect(t, mesh.triangle_count >= 100)
	for triangle in vehicles.mesh_triangles(&mesh) {
		testing.expect(t, int(triangle.a) < mesh.vertex_count)
		testing.expect(t, int(triangle.b) < mesh.vertex_count)
		testing.expect(t, int(triangle.c) < mesh.vertex_count)
	}
}

@(test)
simple_car_solid_mesh_winds_every_component_outward :: proc(t: ^testing.T) {
	mesh := vehicles.simple_car_mesh()
	components := [18]Car_Mesh_Component {
		{0, 12, {0, .28, 0}},
		{12, 12, {0, .60, -.08}},
		{24, 20, {0, .94, -.01}},
		{44, 12, {-1, .31, -1.12}},
		{56, 12, {-1.015, .31, -1.12}},
		{68, 12, {-1, .31, 1.12}},
		{80, 12, {-1.015, .31, 1.12}},
		{92, 12, {1, .31, -1.12}},
		{104, 12, {1.015, .31, -1.12}},
		{116, 12, {1, .31, 1.12}},
		{128, 12, {1.015, .31, 1.12}},
		{140, 12, {0, .30, -1.88}},
		{152, 12, {0, .30, 1.88}},
		{164, 12, {-.58, .61, -1.66}},
		{176, 12, {-.58, .61, 1.66}},
		{188, 12, {.58, .61, -1.66}},
		{200, 12, {.58, .61, 1.66}},
		{212, 0, {}},
	}
	for component in components {
		car_triangle_winds_outward(t, &mesh, component)
	}
	testing.expect(t, mesh.triangle_count == components[len(components) - 1].first_triangle)
}

@(test)
car_spawns_in_entry_range_and_is_selected_before_the_postale :: proc(t: ^testing.T) {
	player_spawn := third_person.Vec3 {
		x = 20,
		y = 4.5,
		z = 30,
	}
	car := vehicles.default_vehicle(vehicles.car_spawn_near(player_spawn))
	car.interaction_radius = 3
	testing.expect(t, car.position.x == player_spawn.x)
	testing.expect(t, car.position.z > player_spawn.z)
	postale := vehicles.default_vehicle(
		{x = player_spawn.x, y = player_spawn.y, z = player_spawn.z - 2.2},
	)
	character := vehicles.Character {
		position = player_spawn,
	}
	selected, entered := vehicles.try_enter_nearest(
		&character,
		[]^vehicles.Vehicle{&car, &postale},
	)
	testing.expect(t, entered)
	testing.expect(t, selected == &car)
	testing.expect(t, character.vehicle == &car && car.driver == &character)
}
