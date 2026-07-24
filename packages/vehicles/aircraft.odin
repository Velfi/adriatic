package vehicles

import wireframe "../wireframe"

// Product-facing wireframes. They face negative Z and deliberately describe
// each airframe's role rather than trying to reproduce presentation meshes.
Aircraft_Wireframe :: struct {
	vertices: [32]wireframe.Vertex,
	edges:    [48]wireframe.Edge,
}

postale_wireframe :: proc() -> Aircraft_Wireframe {
	body := wireframe.Color_Float {r=.82, g=.27, b=.18}; fabric := wireframe.Color_Float {r=.94, g=.82, b=.48}; dark := wireframe.Color_Float {r=.16, g=.12, b=.09}
	return {vertices={
		// Narrow taildragger fuselage, high wing and generous STOL tail.
		{position={-.62,.05,-2.1},color=body},{position={.62,.05,-2.1},color=body},{position={.62,.05,2.0},color=body},{position={-.62,.05,2.0},color=body},{position={-.48,.82,-1.15},color=body},{position={.48,.82,-1.15},color=body},{position={.34,.58,1.72},color=body},{position={-.34,.58,1.72},color=body},
		{position={-7.85,.9,-.1},color=fabric},{position={7.85,.9,-.1},color=fabric},{position={6.4,.9,.65},color=fabric},{position={-6.4,.9,.65},color=fabric},
		{position={-3.2,.55,1.63},color=fabric},{position={3.2,.55,1.63},color=fabric},{position={2.25,.55,2.05},color=fabric},{position={-2.25,.55,2.05},color=fabric},
		{position={0,.58,1.55},color=fabric},{position={0,1.78,2.0},color=fabric},{position={0,.58,2.2},color=fabric},
		{position={0,.38,-2.45},color=dark},{position={0,.38,-3.0},color=dark},{position={-.55,.38,-2.72},color=dark},{position={.55,.38,-2.72},color=dark},
		{position={-.72,-.48,-.72},color=dark},{position={.72,-.48,-.72},color=dark},{position={0,-.58,1.42},color=dark},
		{},{},{},{},{},{},
	}, edges={
		{0,1},{1,2},{2,3},{3,0},{0,4},{1,5},{2,6},{3,7},{4,5},{5,6},{6,7},{7,4},
		{8,9},{9,10},{10,11},{11,8},{8,4},{9,5},{10,6},{11,7}, {12,13},{13,14},{14,15},{15,12},{15,7},{14,6}, {16,17},{17,18},{18,16}, {19,20},{21,22}, {23,24},{24,25},{25,23},{23,0},{24,1},{25,3},
		{},{},{},{},{},{},{},{},{},{},{},
	}}
}

pelican_wireframe :: proc() -> Aircraft_Wireframe {
	hull := wireframe.Color_Float {r=.16, g=.48, b=.72}; wing := wireframe.Color_Float {r=.88, g=.9, b=.82}; engine := wireframe.Color_Float {r=.95, g=.62, b=.2}
	return {vertices={
		// Deep planing hull and broad shoulder wing distinguish the flying boat.
		{position={-.9,-.52,-2.5},color=hull},{position={.9,-.52,-2.5},color=hull},{position={1.12,-.52,2.35},color=hull},{position={-1.12,-.52,2.35},color=hull},{position={-.78,.62,-1.45},color=hull},{position={.78,.62,-1.45},color=hull},{position={.63,.7,1.82},color=hull},{position={-.63,.7,1.82},color=hull},
		{position={-7.85,1.05,-.15},color=wing},{position={7.85,1.05,-.15},color=wing},{position={6.25,1.05,.78},color=wing},{position={-6.25,1.05,.78},color=wing},
		{position={-4.1,.72,-.3},color=engine},{position={-2.45,.72,-.3},color=engine},{position={2.45,.72,-.3},color=engine},{position={4.1,.72,-.3},color=engine},
		{position={-3.45,-.35,.25},color=hull},{position={-3.45,-.35,1.62},color=hull},{position={3.45,-.35,.25},color=hull},{position={3.45,-.35,1.62},color=hull},
		{position={-3.1,.45,1.7},color=wing},{position={3.1,.45,1.7},color=wing},{position={2.1,.45,2.14},color=wing},{position={-2.1,.45,2.14},color=wing},{position={0,.65,1.55},color=wing},{position={0,1.75,2.02},color=wing},{position={0,.65,2.2},color=wing},
		{},{},{},{},{},
	}, edges={
		{0,1},{1,2},{2,3},{3,0},{0,4},{1,5},{2,6},{3,7},{4,5},{5,6},{6,7},{7,4},
		{8,9},{9,10},{10,11},{11,8},{8,4},{9,5},{10,6},{11,7}, {12,13},{14,15},{12,8},{13,8},{14,9},{15,9}, {16,17},{18,19},{16,4},{17,7},{18,5},{19,6}, {20,21},{21,22},{22,23},{23,20},{20,7},{21,6}, {24,25},{25,26},{26,24},
		{},{},{},{},{},{},{},
	}}
}

libellula_wireframe :: proc() -> Aircraft_Wireframe {
	frame := wireframe.Color_Float {r=.22, g=.78, b=.63}; rotor := wireframe.Color_Float {r=.93, g=.93, b=.82}; carriage := wireframe.Color_Float {r=.82, g=.32, b=.2}
	return {vertices={
		// Three large rotors on a triangular frame above a suspended cabin.
		{position={-3.2,1.17,-1},color=frame},{position={3.2,1.17,-1},color=frame},{position={0,1.17,4.54},color=frame},
		{position={-4.55,1.17,-1},color=rotor},{position={-1.85,1.17,-1},color=rotor},{position={3.2,1.17,-2.35},color=rotor},{position={3.2,1.17,.35},color=rotor},{position={-1.18,1.17,3.86},color=rotor},{position={1.18,1.17,5.22},color=rotor},
		{position={-1.45,-.72,-.38},color=carriage},{position={1.45,-.72,-.38},color=carriage},{position={1.08,-.72,1.78},color=carriage},{position={-1.08,-.72,1.78},color=carriage},{position={-1.1,.05,-.15},color=carriage},{position={1.1,.05,-.15},color=carriage},{position={.82,.05,1.5},color=carriage},{position={-.82,.05,1.5},color=carriage},
		{position={-3.2,.55,-1},color=frame},{position={3.2,.55,-1},color=frame},{position={0,.55,4.54},color=frame},
		{},{},{},{},{},{},{},{},{},{},{},{},
	}, edges={
		{0,1},{1,2},{2,0}, {3,4},{5,6},{7,8}, {0,3},{0,4},{1,5},{1,6},{2,7},{2,8},
		{9,10},{10,11},{11,12},{12,9},{13,14},{14,15},{15,16},{16,13},{9,13},{10,14},{11,15},{12,16},
		{0,17},{1,18},{2,19},{17,13},{18,14},{19,15},
		{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},
	}}
}
