package tests

import vehicles "../packages/vehicles"
import "core:testing"

valid_edges :: proc(t: ^testing.T, model: vehicles.Aircraft_Wireframe) {
	for edge in model.edges {
		testing.expect(t, edge.a >= 0 && edge.a < len(model.vertices))
		testing.expect(t, edge.b >= 0 && edge.b < len(model.vertices))
	}
}

@(test)
aircraft_wireframes_express_airframe_roles :: proc(t: ^testing.T) {
	postale := vehicles.postale_wireframe(
		
	); pelican := vehicles.pelican_wireframe(); libellula := vehicles.libellula_wireframe()
	valid_edges(t, postale); valid_edges(t, pelican); valid_edges(t, libellula)
	// The Postale's high wing, Pelican's twin engines/pontoons, and Libellula's
	// triangular rotor plan are intentionally inspectable from their wireframes.
	testing.expect(t, postale.vertices[8].position[1] > postale.vertices[4].position[1])
	testing.expect(
		t,
		pelican.vertices[16].position[0] < -3 && pelican.vertices[18].position[0] > 3,
	)
	testing.expect(
		t,
		libellula.vertices[0].position[0] < 0 &&
		libellula.vertices[1].position[0] > 0 &&
		libellula.vertices[2].position[2] > 4,
	)
}

@(test)
aircraft_wireframes_animate_flaps_and_propellers :: proc(t: ^testing.T) {
	postale := vehicles.postale_wireframe(); vehicles.animate_postale(&postale, 1, .25)
	testing.expect(
		t,
		postale.vertices[10].position[1] < .4 && postale.vertices[10].position[2] > .9,
	)
	testing.expect(t, postale.vertices[19].position[1] < -.2)
	pelican := vehicles.pelican_wireframe(); vehicles.animate_pelican(&pelican, 1, .125)
	testing.expect(
		t,
		pelican.vertices[10].position[1] < .6 && pelican.vertices[12].position[1] < .2,
	)
	libellula := vehicles.libellula_wireframe(); vehicles.animate_libellula(&libellula, .25)
	testing.expect(
		t,
		libellula.vertices[3].position[2] < -2 && libellula.vertices[5].position[2] > -.5,
	)
}

@(test)
procedural_player_aircraft_build_closed_triangle_surfaces :: proc(t: ^testing.T) {
	postale := vehicles.postale_mesh()
	pelican := vehicles.pelican_mesh()
	libellula := vehicles.libellula_mesh()
	meshes := [3]vehicles.Aircraft_Mesh{postale, pelican, libellula}
	for &mesh in meshes {
		testing.expect(t, mesh.vertex_count > 0)
		testing.expect(t, mesh.triangle_count > 0)
		testing.expect(t, mesh.vertex_count == mesh.triangle_count * 3)
		testing.expect(t, mesh.vertex_count < vehicles.AIRCRAFT_MESH_VERTEX_CAPACITY)
		for triangle in vehicles.mesh_triangles(&mesh) {
			testing.expect(t, int(triangle.a) < mesh.vertex_count)
			testing.expect(t, int(triangle.b) < mesh.vertex_count)
			testing.expect(t, int(triangle.c) < mesh.vertex_count)
		}
	}
	testing.expect(t, postale.triangle_count > 300)
	testing.expect(t, pelican.triangle_count > postale.triangle_count)
	testing.expect(t, libellula.triangle_count > 100)
}

first_mesh_part_position :: proc(
	mesh: ^vehicles.Aircraft_Mesh,
	part: vehicles.Aircraft_Mesh_Part,
) -> [3]f32 {
	for vertex in vehicles.mesh_vertices(mesh) {
		if vertex.part == part do return vertex.position
	}
	return {}
}

@(test)
procedural_player_aircraft_meshes_pose_props_and_control_surfaces :: proc(t: ^testing.T) {
	postale := vehicles.postale_mesh()
	postale_flap := first_mesh_part_position(&postale, .Left_Flap)
	postale_prop := first_mesh_part_position(&postale, .Propeller)
	vehicles.animate_postale_mesh(&postale, 1, 1, 1, 1, .25)
	testing.expect(t, first_mesh_part_position(&postale, .Left_Flap) != postale_flap)
	testing.expect(t, first_mesh_part_position(&postale, .Propeller) != postale_prop)

	pelican := vehicles.pelican_mesh()
	left_prop := first_mesh_part_position(&pelican, .Left_Propeller)
	right_prop := first_mesh_part_position(&pelican, .Right_Propeller)
	elevator := first_mesh_part_position(&pelican, .Elevator)
	vehicles.animate_pelican_mesh(&pelican, .5, 1, 1, 1, .125, .125)
	testing.expect(t, first_mesh_part_position(&pelican, .Left_Propeller) != left_prop)
	testing.expect(t, first_mesh_part_position(&pelican, .Right_Propeller) != right_prop)
	testing.expect(t, first_mesh_part_position(&pelican, .Elevator) != elevator)

	libellula := vehicles.libellula_mesh()
	left_rotor := first_mesh_part_position(&libellula, .Left_Rotor)
	right_rotor := first_mesh_part_position(&libellula, .Right_Rotor)
	vehicles.animate_libellula_mesh(&libellula, .25, .25, .25)
	testing.expect(t, first_mesh_part_position(&libellula, .Left_Rotor) != left_rotor)
	testing.expect(t, first_mesh_part_position(&libellula, .Right_Rotor) != right_rotor)
}
