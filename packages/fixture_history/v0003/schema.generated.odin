// Code generated from immutable fixture history. DO NOT EDIT.
// fixture-history-format-version: 1
// fixture-history-schema-version: 3
// fixture-history-manifest-sha256: 210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f
package fixture_v0003

FIXTURE_SCHEMA_VERSION :: 3

// fixture-history-id: adriatic:packages/architecture.City_Alley
History_Type_0000 :: struct {
	start_x: f32,
	start_z: f32,
	end_x: f32,
	end_z: f32,
	half_width: f32,
}

// fixture-history-id: adriatic:packages/architecture.City_Lamp
History_Type_0001 :: struct {
	x: f32,
	z: f32,
	yaw: f32,
}

// fixture-history-id: adriatic:packages/architecture.City_Parcel
History_Type_0002 :: struct {
	corners: [4][2]f32,
	frontage_width: f32,
	depth: f32,
	density: f32,
	seed: u32,
	attached: bool,
	alley_frontage: bool,
}

// fixture-history-id: adriatic:packages/architecture.City_Plan
History_Type_0003 :: struct {
	structures: [dynamic]History_Type_0087,
	count: int,
	parcels: [dynamic]History_Type_0002,
	parcel_count: int,
	alleys: [dynamic]History_Type_0000,
	alley_count: int,
	lamps: [dynamic]History_Type_0001,
	lamp_count: int,
}

// fixture-history-id: adriatic:packages/atmosphere.Atmosphere
History_Type_0004 :: struct {
	seed: u32,
	world_minutes: f32,
	world_days: f32,
	lunar_days: f32,
	front_seconds: f32,
	weather: History_Type_0006,
	override: History_Type_0005,
	paused: bool,
}

// fixture-history-id: adriatic:packages/atmosphere.Weather_Preset
History_Type_0005 :: enum int {
	Automatic = 0,
	Clear = 1,
	Windy = 2,
	Storm = 3,
}

// fixture-history-id: adriatic:packages/atmosphere.Weather_State
History_Type_0006 :: struct {
	cloud_cover: f32,
	precipitation: f32,
	haze: f32,
	severity: f32,
	wind: [2]f32,
}

// fixture-history-id: adriatic:packages/boats.Agent
History_Type_0007 :: struct {
	class: History_Type_0009,
	position: History_Type_0012,
	velocity: History_Type_0012,
	yaw: f32,
	speed: f32,
	throttle: f32,
	behavior: History_Type_0008,
	route: [8]History_Type_0012,
	route_count: int,
	route_index: int,
	schedule: [5]History_Type_0010,
	schedule_count: int,
	loiter_center: History_Type_0012,
	loiter_radius: f32,
	loiter_phase: f32,
	mooring_position: History_Type_0012,
	mooring_yaw: f32,
	wake: [48]History_Type_0013,
	wake_count: int,
	wake_distance: f32,
}

// fixture-history-id: adriatic:packages/boats.Behavior
History_Type_0008 :: enum u8 {
	Transit = 0,
	Patrol = 1,
	Loiter = 2,
	Moored = 3,
}

// fixture-history-id: adriatic:packages/boats.Class
History_Type_0009 :: enum u8 {
	Motor = 0,
	Sail = 1,
	Fishing = 2,
	Tug = 3,
	Dinghy = 4,
}

// fixture-history-id: adriatic:packages/boats.Schedule_Entry
History_Type_0010 :: struct {
	start_minutes: f32,
	end_minutes: f32,
	behavior: History_Type_0008,
	speed_scale: f32,
}

// fixture-history-id: adriatic:packages/boats.Traffic
History_Type_0011 :: struct {
	agents: [32]History_Type_0007,
	count: int,
	clock: f32,
}

// fixture-history-id: adriatic:packages/boats.Vec2
History_Type_0012 :: [2]f32

// fixture-history-id: adriatic:packages/boats.Wake_Sample
History_Type_0013 :: struct {
	position: History_Type_0012,
	direction: History_Type_0012,
	age: f32,
	lifetime: f32,
	width: f32,
	strength: f32,
}

// fixture-history-id: adriatic:packages/buildings.Archetype
History_Type_0014 :: enum u8 {
	Legacy = 0,
	Dwelling = 1,
	Townhouse = 2,
	Shop_House = 3,
	Workshop = 4,
	Farmstead = 5,
	Barn_Granary = 6,
	Mill = 7,
	Fishery = 8,
	Storehouse = 9,
	Campanile = 10,
	Palace_Loggia = 11,
	Church = 12,
	Monastery = 13,
	Fortress_Gate = 14,
	Harbor_Office = 15,
	Market_Hall = 16,
	Cycladic_Bell = 17,
}

// fixture-history-id: adriatic:packages/buildings.Identity
History_Type_0015 :: struct {
	archetype: History_Type_0014,
	purpose: History_Type_0017,
	region: History_Type_0018,
	landmark_kind: History_Type_0016,
}

// fixture-history-id: adriatic:packages/buildings.Landmark_Kind
History_Type_0016 :: enum u8 {
	None = 0,
	Campanile = 1,
	Palace_Loggia = 2,
	Church = 3,
	Monastery = 4,
	Fortress_Gate = 5,
	Harbor_Office = 6,
	Market_Hall = 7,
	Cycladic_Bell = 8,
}

// fixture-history-id: adriatic:packages/buildings.Purpose
History_Type_0017 :: enum u8 {
	Dwelling = 0,
	Farmstead = 1,
	Barn_Granary = 2,
	Workshop = 3,
	Inn_Shop = 4,
	Mill = 5,
	Fishery = 6,
	Storehouse = 7,
}

// fixture-history-id: adriatic:packages/buildings.Region
History_Type_0018 :: enum u8 {
	Adriatic = 0,
	Aegean = 1,
}

// fixture-history-id: adriatic:packages/chase_camera.State
History_Type_0019 :: struct {
	pose: History_Type_0090,
	base_pose: History_Type_0090,
	orbit_yaw: f32,
	orbit_pitch: f32,
	focal_length: f32,
	shake_phase: f32,
	shake_intensity: f32,
	previous_target_position: History_Type_0032,
	initialized: bool,
}

// fixture-history-id: adriatic:packages/farmland.Crop
History_Type_0020 :: enum u8 {
	Wheat = 0,
	Olive = 1,
	Vineyard = 2,
	Fallow = 3,
	Clover = 4,
}

// fixture-history-id: adriatic:packages/farmland.Parcel
History_Type_0021 :: struct {
	min_x: int,
	min_z: int,
	max_x: int,
	max_z: int,
	crop: History_Type_0020,
	row_axis_x: bool,
	phase: f32,
	tint: f32,
}

// fixture-history-id: adriatic:packages/farmland.Plan
History_Type_0022 :: struct {
	seed: u32,
	width: int,
	height: int,
	tradition: History_Type_0023,
	parcels: [24]History_Type_0021,
	parcel_count: int,
	valid: bool,
}

// fixture-history-id: adriatic:packages/farmland.Tradition
History_Type_0023 :: enum u8 {
	Ancient_Enclosure = 0,
	Parliamentary_Enclosure = 1,
}

// fixture-history-id: adriatic:packages/flight.Airframe
History_Type_0024 :: struct {
	flight_layout: u8,
	mass_kg: f32,
	maximum_gross_mass_kg: f32,
	wing_area: f32,
	lift_scale: f32,
	drag_scale: f32,
	stall_speed: f32,
	maximum_speed: f32,
	rated_power_per_engine_kw: f32,
	propeller_efficiency: f32,
	static_thrust_per_engine: f32,
	engine_count: f32,
	wing_incidence_degrees: f32,
	lift_curve_slope_per_degree: f32,
	zero_lift_angle_degrees: f32,
	critical_angle_degrees: f32,
	negative_critical_angle_degrees: f32,
	post_stall_angle_degrees: f32,
	post_stall_lift_coefficient: f32,
	induced_drag_factor: f32,
	trim_angle_of_attack_degrees: f32,
	pitch_stability: f32,
	pitch_damping: f32,
	roll_stability: f32,
	roll_damping: f32,
	yaw_stability: f32,
	yaw_damping: f32,
	pitch_control_scale: f32,
	roll_control_scale: f32,
	yaw_control_scale: f32,
	water_capable: bool,
	water_planing_start_speed: f32,
	water_planing_full_speed: f32,
	water_planing_reference_speed: f32,
	water_plow_drag_scale: f32,
}

// fixture-history-id: adriatic:packages/flight.Basis
History_Type_0025 :: struct {
	forward: History_Type_0032,
	up: History_Type_0032,
	right: History_Type_0032,
}

// fixture-history-id: adriatic:packages/flight.Body_State
History_Type_0026 :: struct {
	position: History_Type_0032,
	velocity: History_Type_0032,
	angular_velocity: History_Type_0032,
	basis: History_Type_0025,
}

// fixture-history-id: adriatic:packages/flight.Runtime
History_Type_0027 :: struct {
	engine_output: f32,
	control_authority: f32,
	drag_multiplier: f32,
	stall_speed_modifier: f32,
	controls_damaged: bool,
}

// fixture-history-id: adriatic:packages/flight.Telemetry
History_Type_0028 :: struct {
	airspeed: f32,
	angle_of_attack_degrees: f32,
	effective_stall_speed: f32,
	lift_coefficient: f32,
	is_stalling: bool,
}

// fixture-history-id: adriatic:packages/flight.Tri_Rotor_Airframe
History_Type_0029 :: struct {
	mass_kg: f32,
	maximum_gross_mass_kg: f32,
	maximum_collective_force: f32,
	attitude_torque: f32,
	yaw_torque: f32,
	leveling_strength: f32,
	angular_damping: f32,
	maximum_tilt_angle: f32,
	ground_effect_height: f32,
	ground_effect_bonus: f32,
	safe_landing_speed: f32,
}

// fixture-history-id: adriatic:packages/flight.Tri_Rotor_Runtime
History_Type_0030 :: struct {
	left_engine_output: f32,
	right_engine_output: f32,
	rear_engine_output: f32,
	auto_level: bool,
	ground_distance: f32,
}

// fixture-history-id: adriatic:packages/flight.Tri_Rotor_Telemetry
History_Type_0031 :: struct {
	rotor_thrusts: History_Type_0032,
	rotor_rpm_normalized: History_Type_0032,
	total_thrust: f32,
}

// fixture-history-id: adriatic:packages/flight.Vec3
History_Type_0032 :: [3]f32

// fixture-history-id: adriatic:packages/libellula.Runtime
History_Type_0033 :: struct {
	body: History_Type_0026,
	vehicle: History_Type_0105,
	airframe: History_Type_0029,
	flight_runtime: History_Type_0030,
	telemetry: History_Type_0031,
	tuning: History_Type_0034,
	spawn_position: History_Type_0032,
	spawn_basis: History_Type_0025,
	throttle: f32,
	pitch: f32,
	roll: f32,
	yaw: f32,
	rotor_turns: History_Type_0032,
	grounded: bool,
	was_grounded: bool,
	crashed: bool,
	lift_active: bool,
}

// fixture-history-id: adriatic:packages/libellula.Tuning
History_Type_0034 :: struct {
	throttle_response: f32,
	climb_speed: f32,
	descent_speed: f32,
	vertical_speed_gain: f32,
	control_response: f32,
	control_release: f32,
	cyclic_scale: f32,
	cyclic_expo: f32,
	yaw_scale: f32,
	maximum_tilt_radians: f32,
	attitude_gain: f32,
	attitude_rate_gain: f32,
	horizontal_damping: f32,
	ground_clearance: f32,
	ground_friction: f32,
	safe_touchdown_speed: f32,
	safe_exit_speed: f32,
	rotor_idle_rate: f32,
	rotor_full_rate: f32,
}

// fixture-history-id: adriatic:packages/marina.Basin_Style
History_Type_0035 :: enum u8 {
	Fishing_Quay = 0,
	Civic_Marina = 1,
	Island_Harbour = 2,
	Working_Port = 3,
	Stone_Cove = 4,
	Ferry_Quay = 5,
	Boat_Yard = 6,
	Lagoon_Marina = 7,
}

// fixture-history-id: adriatic:packages/marina.Berth_Kind
History_Type_0036 :: enum u8 {
	Slip = 0,
	Swing_Mooring = 1,
}

// fixture-history-id: adriatic:packages/marina.Boundary_Form
History_Type_0037 :: enum u8 {
	Enclosed_Basin = 0,
	Wide_Twin_Moles = 1,
	Offset_West = 2,
	Offset_East = 3,
	Open_Cove = 4,
}

// fixture-history-id: adriatic:packages/marina.Cell
History_Type_0038 :: enum u8 {
	Water = 0,
	Land = 1,
	Quay = 2,
	Breakwater = 3,
	Natural_Jetty = 4,
	Main_Pier = 5,
	Finger_Pier = 6,
	Slip = 7,
	Mooring = 8,
	Channel = 9,
	Building = 10,
	Props = 11,
}

// fixture-history-id: adriatic:packages/marina.Plan
History_Type_0039 :: struct {
	seed: u32,
	layout_seed: u32,
	candidate_index: int,
	candidates_evaluated: int,
	style: History_Type_0035,
	boundary_form: History_Type_0037,
	shoreline_form: History_Type_0045,
	section_form_counts: [9]int,
	cells: [567]History_Type_0038,
	segments: [96]History_Type_0043,
	segment_count: int,
	slips: [40]History_Type_0046,
	slip_count: int,
	props: [48]History_Type_0040,
	prop_count: int,
	route: History_Type_0042,
	office: History_Type_0047,
	world_conditioned: bool,
	world_origin: History_Type_0047,
	world_yaw: f32,
	spacing_density: f32,
	target_fill_density: f32,
	fill_density: f32,
	fill_density_error: f32,
	berth_spacing_badness: f32,
	structure_overlap_badness: f32,
	site_conformance_badness: f32,
	spacing_badness_density: f32,
	generation_quality: f32,
	valid: bool,
}

// fixture-history-id: adriatic:packages/marina.Prop
History_Type_0040 :: struct {
	kind: History_Type_0041,
	position: History_Type_0047,
	yaw: f32,
}

// fixture-history-id: adriatic:packages/marina.Prop_Kind
History_Type_0041 :: enum u8 {
	Lamp = 0,
	Beacon = 1,
	Bollard = 2,
	Crates = 3,
	Nets = 4,
}

// fixture-history-id: adriatic:packages/marina.Route
History_Type_0042 :: struct {
	points: [8]History_Type_0047,
	count: int,
}

// fixture-history-id: adriatic:packages/marina.Segment
History_Type_0043 :: struct {
	kind: History_Type_0044,
	a: History_Type_0047,
	b: History_Type_0047,
	width: f32,
}

// fixture-history-id: adriatic:packages/marina.Segment_Kind
History_Type_0044 :: enum u8 {
	Quay = 0,
	Breakwater = 1,
	Natural_Jetty = 2,
	Main_Pier = 3,
	Finger_Pier = 4,
}

// fixture-history-id: adriatic:packages/marina.Shoreline_Form
History_Type_0045 :: enum u8 {
	Straight_Quay = 0,
	West_Apron = 1,
	East_Apron = 2,
	Split_Aprons = 3,
	Stepped_Quays = 4,
}

// fixture-history-id: adriatic:packages/marina.Slip
History_Type_0046 :: struct {
	position: History_Type_0047,
	yaw: f32,
	class: History_Type_0009,
	occupied: bool,
	kind: History_Type_0036,
}

// fixture-history-id: adriatic:packages/marina.Vec2
History_Type_0047 :: struct {
	x: f32,
	z: f32,
}

// fixture-history-id: adriatic:packages/mouse_tail.Config
History_Type_0048 :: struct {
	segment_length: f32,
	radius: f32,
	gravity: f32,
	damping: f32,
	constraint_iterations: int,
	substeps: int,
	root_stiffness: f32,
	root_damping: f32,
	bend_stiffness: f32,
	surface_friction: f32,
}

// fixture-history-id: adriatic:packages/mouse_tail.Point
History_Type_0049 :: struct {
	position: History_Type_0095,
	previous: History_Type_0095,
}

// fixture-history-id: adriatic:packages/mouse_tail.State
History_Type_0050 :: struct {
	points: [13]History_Type_0049,
	last_root: History_Type_0095,
	initialized: bool,
}

// fixture-history-id: adriatic:packages/particles.Dust_Surface
History_Type_0051 :: enum u8 {
	Grass = 0,
	Asphalt = 1,
	Gravel = 2,
	Cobblestone = 3,
	Dirt = 4,
	Sand = 5,
}

// fixture-history-id: adriatic:packages/particles.Particle
History_Type_0052 :: struct {
	position: History_Type_0054,
	velocity: History_Type_0054,
	life: f32,
	max_life: f32,
	size: f32,
	seed: u32,
}

// fixture-history-id: adriatic:packages/particles.Petal_Effects
History_Type_0053 :: struct {
	particles: [192]History_Type_0052,
	count: int,
	spawn: f32,
	seed: u32,
}

// fixture-history-id: adriatic:packages/particles.Vec3
History_Type_0054 :: struct {
	x: f32,
	y: f32,
	z: f32,
}

// fixture-history-id: adriatic:packages/particles.Vehicle_Effects
History_Type_0055 :: struct {
	dust: [256]History_Type_0056,
	dust_count: int,
	dust_spawn: f32,
	seed: u32,
}

// fixture-history-id: adriatic:packages/particles.Vehicle_Particle
History_Type_0056 :: struct {
	position: History_Type_0054,
	velocity: History_Type_0054,
	life: f32,
	max_life: f32,
	size: f32,
	seed: u32,
	surface: History_Type_0051,
}

// fixture-history-id: adriatic:packages/particles.Wing_Trail_Particle
History_Type_0057 :: struct {
	position: History_Type_0054,
	velocity: History_Type_0054,
	life: f32,
	max_life: f32,
	size: f32,
	seed: u32,
	side: u8,
	curve: f32,
}

// fixture-history-id: adriatic:packages/particles.Wing_Trails
History_Type_0058 :: struct {
	particles: [192]History_Type_0057,
	count: int,
	spawn: f32,
	seed: u32,
}

// fixture-history-id: adriatic:packages/postale.Landing_Impact
History_Type_0059 :: struct {
	outcome: History_Type_0060,
	sink_speed: f32,
	weight_force: f32,
	impact_force: f32,
	load_factor: f32,
	damage: f32,
}

// fixture-history-id: adriatic:packages/postale.Landing_Outcome
History_Type_0060 :: enum int {
	None = 0,
	Smooth = 1,
	Landed = 2,
	Hard_Landing = 3,
	Crash = 4,
}

// fixture-history-id: adriatic:packages/postale.Runtime
History_Type_0061 :: struct {
	body: History_Type_0026,
	vehicle: History_Type_0105,
	airframe: History_Type_0024,
	flight_runtime: History_Type_0027,
	telemetry: History_Type_0028,
	throttle: f32,
	flap_fraction: f32,
	propeller_turns: f32,
	pitch: f32,
	roll: f32,
	yaw: f32,
	grounded: bool,
	crashed: bool,
	was_grounded: bool,
	grounded_time: f32,
	takeoff_armed: bool,
	gear_compression: f32,
	gear_force: f32,
	structural_damage: f32,
	last_landing: History_Type_0059,
	landing_feedback_seconds: f32,
	spawn_position: History_Type_0032,
	spawn_basis: History_Type_0025,
	tuning: History_Type_0062,
}

// fixture-history-id: adriatic:packages/postale.Tuning
History_Type_0062 :: struct {
	ground_clearance: f32,
	safe_bank_radians: f32,
	gear_compression_distance: f32,
	gear_damping_ratio: f32,
	smooth_landing_load: f32,
	hard_landing_load: f32,
	ultimate_landing_load: f32,
	safe_exit_speed: f32,
	takeoff_stall_speed_scale: f32,
	throttle_up_rate: f32,
	throttle_down_rate: f32,
	pitch_rate_increase: f32,
	pitch_rate_decrease: f32,
	roll_rate_increase: f32,
	roll_rate_decrease: f32,
	yaw_rate_increase: f32,
	yaw_rate_decrease: f32,
	flap_response: f32,
	flap_auto_throttle: f32,
	flap_auto_speed: f32,
	ground_brake: f32,
	ground_coast: f32,
	ground_steer_fast: f32,
	ground_steer_slow: f32,
	takeoff_throttle: f32,
	takeoff_speed_scale: f32,
	takeoff_pitch: f32,
	takeoff_ground_time: f32,
	takeoff_vertical_assist: f32,
	propeller_base_rate: f32,
	propeller_throttle_rate: f32,
}

// fixture-history-id: adriatic:packages/quest.Node_ID
History_Type_0063 :: distinct int

// fixture-history-id: adriatic:packages/quest.State
History_Type_0064 :: struct {
	definition_id: string,
	node_count: int,
	statuses: [128]History_Type_0065,
	completion_counts: [128]int,
	activated_at: [128]u64,
	completed_at: [128]u64,
	revision: u64,
}

// fixture-history-id: adriatic:packages/quest.Status
History_Type_0065 :: enum u8 {
	Locked = 0,
	Available = 1,
	Active = 2,
	Completed = 3,
}

// fixture-history-id: adriatic:packages/roads.Edge
History_Type_0066 :: struct {
	from: int,
	to: int,
	control_from: History_Type_0070,
	control_to: History_Type_0070,
	half_width: f32,
	shoulder_width: f32,
	pavement: History_Type_0069,
}

// fixture-history-id: adriatic:packages/roads.Graph
History_Type_0067 :: struct {
	nodes: [64]History_Type_0068,
	node_count: int,
	edges: [128]History_Type_0066,
	edge_count: int,
}

// fixture-history-id: adriatic:packages/roads.Node
History_Type_0068 :: struct {
	position: History_Type_0070,
	up: History_Type_0070,
	junction_radius: f32,
}

// fixture-history-id: adriatic:packages/roads.Pavement
History_Type_0069 :: enum u8 {
	Asphalt = 0,
	Gravel = 1,
	Cobblestone = 2,
	Dirt = 3,
}

// fixture-history-id: adriatic:packages/roads.Vec3
History_Type_0070 :: [3]f32

// fixture-history-id: adriatic:packages/story.Airfield_Errand_Stage
History_Type_0071 :: enum int {
	Not_Offered = 0,
	Westbound = 1,
	Eastbound = 2,
	Completed = 3,
}

// fixture-history-id: adriatic:packages/story.Delivery
History_Type_0072 :: struct {
	active: bool,
	kind: History_Type_0073,
	from: History_Type_0076,
	to: History_Type_0076,
	origin: History_Type_0074,
	destination: History_Type_0074,
	subject: string,
}

// fixture-history-id: adriatic:packages/story.Delivery_Kind
History_Type_0073 :: enum int {
	None = 0,
	First_Letter = 1,
	First_Reply = 2,
	Regatta_Invitation = 3,
	Regatta_Acceptance = 4,
	Repeat_Eastbound = 5,
	Repeat_Westbound = 6,
}

// fixture-history-id: adriatic:packages/story.Island
History_Type_0074 :: enum int {
	West = 0,
	East = 1,
}

// fixture-history-id: adriatic:packages/story.Repair_Stage
History_Type_0075 :: enum int {
	Not_Seen = 0,
	Crash_Reported = 1,
	Diagnosed = 2,
	Patched = 3,
	Repaired = 4,
}

// fixture-history-id: adriatic:packages/story.Resident
History_Type_0076 :: enum int {
	Marta = 0,
	Gerta = 1,
	Niko = 2,
	Iva = 3,
	Bojan = 4,
	Zora = 5,
}

// fixture-history-id: adriatic:packages/story.Romance_Stage
History_Type_0077 :: enum int {
	Unintroduced = 0,
	First_Letter = 1,
	Corresponding = 2,
	Invitation = 3,
	Meeting = 4,
	Together = 5,
}

// fixture-history-id: adriatic:packages/story.State
History_Type_0078 :: struct {
	quest: History_Type_0064,
	romance: History_Type_0077,
	repair: History_Type_0075,
	airfield_errand: History_Type_0071,
	delivery: History_Type_0072,
	completed_deliveries: int,
	repeat_deliveries: int,
	stamps_earned: int,
	has_wing_patch: bool,
	tarot_readings: int,
	tarot_seed: u32,
	tarot_last_moment: u32,
	tarot_layout: History_Type_0080,
}

// fixture-history-id: adriatic:packages/tarot.Card
History_Type_0079 :: distinct u8

// fixture-history-id: adriatic:packages/tarot.Layout
History_Type_0080 :: struct {
	spread: History_Type_0083,
	placements: [10]History_Type_0082,
	count: int,
	seed: u32,
}

// fixture-history-id: adriatic:packages/tarot.Orientation
History_Type_0081 :: enum int {
	Upright = 0,
	Reversed = 1,
}

// fixture-history-id: adriatic:packages/tarot.Placement
History_Type_0082 :: struct {
	card: History_Type_0079,
	orientation: History_Type_0081,
	position: string,
}

// fixture-history-id: adriatic:packages/tarot.Spread
History_Type_0083 :: enum int {
	Single = 0,
	Three_Card = 1,
	Celtic_Cross = 2,
}

// fixture-history-id: adriatic:packages/terrain.Clipmap_Level
History_Type_0084 :: struct {
	cell_size: f32,
	origin_x: f32,
	origin_z: f32,
	heights: [65536]f32,
	material: [65536]f32,
}

// fixture-history-id: adriatic:packages/terrain.Formation_Kind
History_Type_0085 :: enum int {
	Box = 0,
	Rock = 1,
	Spire = 2,
	Mountain = 3,
	Ridge = 4,
	Cliff = 5,
	Foliage = 6,
	Architecture = 7,
}

// fixture-history-id: adriatic:packages/terrain.Project
History_Type_0086 :: struct {
	levels: [6]History_Type_0084,
	sea_level: f32,
	revision: u64,
	structures: [dynamic]History_Type_0087,
	structure_count: int,
	next_structure_id: u64,
	road_graph: History_Type_0067,
	city_density: [65536]u8,
	climbing_leaf_density: [65536]u8,
}

// fixture-history-id: adriatic:packages/terrain.Structure
History_Type_0087 :: struct {
	id: u64,
	group_id: u64,
	center_x: f32,
	center_z: f32,
	width: f32,
	depth: f32,
	base_y: f32,
	height: f32,
	rotation: f32,
	color: [4]u8,
	kind: History_Type_0085,
	seed: u32,
	building: History_Type_0015,
}

// fixture-history-id: adriatic:packages/terrain.Tool
History_Type_0088 :: enum int {
	Raise = 0,
	Smooth = 1,
	Paint = 2,
	Structure = 3,
}

// fixture-history-id: adriatic:packages/third_person.Camera
History_Type_0089 :: struct {
	yaw_radians: f32,
	pitch_radians: f32,
	distance: f32,
	height: f32,
}

// fixture-history-id: adriatic:packages/third_person.Camera_Pose
History_Type_0090 :: struct {
	position: History_Type_0095,
	target: History_Type_0095,
}

// fixture-history-id: adriatic:packages/third_person.Camera_Slot
History_Type_0091 :: enum u8 {
	Player = 0,
	Inspection = 1,
	Cutaway = 2,
	Count = 3,
}

// fixture-history-id: adriatic:packages/third_person.Camera_System
History_Type_0092 :: struct {
	poses: [3]History_Type_0090,
	active: History_Type_0091,
}

// fixture-history-id: adriatic:packages/third_person.Config
History_Type_0093 :: struct {
	move_speed: f32,
	run_speed: f32,
	ground_acceleration: f32,
	ground_deceleration: f32,
	run_acceleration: f32,
	run_deceleration: f32,
	run_steering_speed: f32,
	drift_min_speed: f32,
	drift_charge_seconds: f32,
	boost_speed: f32,
	boost_acceleration: f32,
	boost_duration: f32,
	reversal_braking: f32,
	reversal_speed: f32,
	facing_turn_speed: f32,
	air_acceleration: f32,
	jump_speed: f32,
	gravity: f32,
	slope_gravity_scale: f32,
	max_slope_acceleration: f32,
}

// fixture-history-id: adriatic:packages/third_person.State
History_Type_0094 :: struct {
	position: History_Type_0095,
	velocity: History_Type_0095,
	facing_yaw_radians: f32,
	grounded: bool,
	turn_amount: f32,
	brake_amount: f32,
	ground_normal: History_Type_0095,
	running: bool,
	drifting: bool,
	drift_charge: f32,
	boost_seconds: f32,
}

// fixture-history-id: adriatic:packages/third_person.Vec3
History_Type_0095 :: [3]f32

// fixture-history-id: adriatic:packages/vehicles.Aircraft_Fleet
History_Type_0096 :: struct {
	slots: [8]History_Type_0098,
	count: int,
	active: History_Type_0097,
}

// fixture-history-id: adriatic:packages/vehicles.Aircraft_Kind
History_Type_0097 :: enum u8 {
	Postale = 0,
	Libellula = 1,
	Libellula_Mk2 = 2,
}

// fixture-history-id: adriatic:packages/vehicles.Aircraft_Slot
History_Type_0098 :: struct {
	kind: History_Type_0097,
	name: string,
	available: bool,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Drive_State
History_Type_0099 :: struct {
	velocity: History_Type_0095,
	wheel_speed: f32,
	steering: f32,
	yaw_rate: f32,
	handbrake_amount: f32,
	body_roll: f32,
	body_pitch: f32,
	acceleration_feedback: f32,
	surface_longitudinal_grip: f32,
	surface_lateral_grip: f32,
	surface_rolling_resistance: f32,
	slip_amount: f32,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Drive_Tune
History_Type_0100 :: struct {
	acceleration: f32,
	brake: f32,
	reverse_acceleration: f32,
	max_forward: f32,
	max_reverse: f32,
	steering_response: f32,
	yaw_response: f32,
	turn_curvature: f32,
	max_yaw_rate: f32,
	high_speed_steering: f32,
	reverse_steering: f32,
	lateral_grip: f32,
	handbrake_grip: f32,
	coast_deceleration: f32,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Trailer_State
History_Type_0101 :: struct {
	velocity: History_Type_0095,
	yaw_rate: f32,
	reaction_force: History_Type_0095,
	body_roll: f32,
	body_pitch: f32,
	wheel_rotation: f32,
}

// fixture-history-id: adriatic:packages/vehicles.Character
History_Type_0102 :: struct {
	position: History_Type_0095,
	facing_yaw_radians: f32,
	mode: History_Type_0104,
}

// fixture-history-id: adriatic:packages/vehicles.Fixture_Occupant
History_Type_0103 :: enum u8 {
	On_Foot = 0,
	Car = 1,
	Postale = 2,
	Libellula = 3,
	Libellula_Mk2 = 4,
}

// fixture-history-id: adriatic:packages/vehicles.Occupancy_Mode
History_Type_0104 :: enum int {
	On_Foot = 0,
	Driving = 1,
}

// fixture-history-id: adriatic:packages/vehicles.Vehicle
History_Type_0105 :: struct {
	position: History_Type_0095,
	yaw_radians: f32,
	interaction_radius: f32,
	exit_distance: f32,
	locked: bool,
}

// fixture-history-id: adriatic:src.Authoring_Tool
History_Type_0106 :: enum int {
	Sculpt = 0,
	Smooth = 1,
	Paint = 2,
	Formations = 3,
	Foliage = 4,
	Ridge = 5,
	Cliff = 6,
	Building = 7,
	Marina = 8,
	Farm = 9,
	ClimbingLeaves = 10,
	Roads = 11,
	GreekAssets = 12,
}

// fixture-history-id: adriatic:src.Camera_Tweak
History_Type_0107 :: struct {
	editor_camera: History_Type_0089,
	editor_focus: History_Type_0095,
	player_camera: History_Type_0089,
	flight_orbit_yaw: f32,
	flight_orbit_pitch: f32,
}

// fixture-history-id: adriatic:src.Curve_Point
History_Type_0108 :: struct {
	x: f32,
	z: f32,
}

// fixture-history-id: adriatic:src.Editor_UI_State
History_Type_0109 :: struct {
	left_collapsed: bool,
	inspector_collapsed: bool,
}

// fixture-history-id: adriatic:src.Farm_Instance
History_Type_0110 :: struct {
	plan: History_Type_0022,
	origin_x: f32,
	origin_z: f32,
	yaw: f32,
	scale_x: f32,
	scale_z: f32,
}

// fixture-history-id: adriatic:src.Fixture
Fixture :: struct {
	project: History_Type_0086,
	authoring_tool: History_Type_0106,
	editor_ui: History_Type_0109,
	tool: History_Type_0088,
	radius: f32,
	strength: f32,
	hardness: f32,
	structure_selected: int,
	structure_kind: History_Type_0085,
	structure_auto_kind: bool,
	structure_force_box: bool,
	structure_cliff_mode: bool,
	structure_scatter_mode: bool,
	structure_scatter_count: int,
	formation_brush_radius: f32,
	formation_brush_strength: f32,
	formation_brush_hardness: f32,
	foliage_hedgerow_mode: bool,
	architecture_node_mode: bool,
	architecture_paint_mode: bool,
	architecture_city_plan: History_Type_0003,
	architecture_brush_radius: f32,
	architecture_brush_strength: f32,
	architecture_brush_hardness: f32,
	marina_paint_mode: bool,
	marina_authored: bool,
	marina_authored_plan: History_Type_0039,
	marina_brush_radius: f32,
	farm_paint_mode: bool,
	farm_brush_radius: f32,
	farms: [16]History_Type_0110,
	farm_count: int,
	climbing_leaf_paint_mode: bool,
	climbing_leaf_brush_radius: f32,
	climbing_leaf_brush_strength: f32,
	climbing_leaf_brush_hardness: f32,
	greek_asset_selected: int,
	greek_asset_rotation: f32,
	greek_asset_scale: f32,
	greek_placements: [64]History_Type_0112,
	greek_placement_count: int,
	greek_placement_selected: int,
	greek_placement_mode: bool,
	curve_points: [48]History_Type_0108,
	curve_point_count: int,
	curve_mode: bool,
	curve_cliff_mode: bool,
	curve_width: f32,
	curve_height: f32,
	road_mode: bool,
	road_selected_node: int,
	road_width: f32,
	road_shoulder_width: f32,
	road_pavement: History_Type_0069,
	in_map: bool,
	player: History_Type_0094,
	player_stride_phase: f32,
	player_gait_weight: f32,
	player_airborne_weight: f32,
	player_vertical_pose: f32,
	player_turn_pose: f32,
	player_brake_pose: f32,
	player_posted_idle_seconds: f32,
	player_posted_weight: f32,
	player_scurry_weight: f32,
	player_scurry_lean: f32,
	player_scurry_lean_velocity: f32,
	player_scurry_compression: f32,
	player_scurry_compression_velocity: f32,
	player_animation_previous_speed: f32,
	player_tail: History_Type_0050,
	camera: History_Type_0089,
	camera_pose: History_Type_0090,
	cameras: History_Type_0092,
	flight_camera: History_Type_0019,
	editor_camera: History_Type_0089,
	editor_focus: History_Type_0095,
	boat_traffic: History_Type_0011,
	marina_dinghy_borrowed: bool,
	occupant: History_Type_0103,
	pilot: History_Type_0102,
	car: History_Type_0105,
	car_drive: History_Type_0099,
	car_trailer: History_Type_0101,
	car_trailer_attached: bool,
	car_trailer_position: History_Type_0095,
	car_trailer_yaw: f32,
	postale: History_Type_0061,
	libellula: History_Type_0033,
	aircraft: History_Type_0096,
	postale_visible: bool,
	libellula_visible: bool,
	vehicle_showcase_scene: bool,
	wildflower_lab_scene: bool,
	vehicle_showcase_target: string,
	shadow_lab_scene: bool,
	active_lab_scene: string,
	settlement_vertical_map: bool,
	settlement_plan: History_Type_0129,
	settlement_diagnostic_layer: int,
	shadow_lab_collection: int,
	shadow_lab_lighting: int,
	vehicle_paint_scene: bool,
	vehicle_paint_yaw: f32,
	vehicle_paint_pitch: f32,
	vehicle_paint_distance: f32,
	vehicle_paint_panel_visible: bool,
	vehicle_paint_color: int,
	vehicle_paint_secondary_color: int,
	vehicle_paint_pattern: int,
	vehicle_paint_pattern_size: int,
	vehicle_paint_pattern_rotation: f32,
	vehicle_paint_shape_kind: int,
	vehicle_paint_shape_size: int,
	vehicle_paint_shape_rotation: f32,
	vehicle_paint_tool: History_Type_0144,
	vehicle_paint_component: int,
	vehicle_paint_component_mask: [5]bool,
	vehicle_paint_saved_postale_position: History_Type_0032,
	vehicle_paint_saved_libellula_position: History_Type_0032,
	vehicle_paint_brush_radius: int,
	vehicle_paint_brush_hardness: f32,
	vehicle_paint_brush_strength: f32,
	vehicle_paint_erase: bool,
	vehicle_paint_symmetry: bool,
	vehicle_paint_layers: [3][8388608]u8,
	vehicle_paint_components: [5]bool,
	attendant_position: History_Type_0095,
	gerta_position: History_Type_0095,
	story_state: History_Type_0078,
	tracked_quest_node: History_Type_0063,
	quest_tracking_suppressed: bool,
	quest_tracking_revision: u64,
	camera_target_lock: bool,
	atmosphere: History_Type_0004,
	vehicle_effects: History_Type_0055,
	wing_trails: History_Type_0058,
	petal_effects: History_Type_0053,
	tweak: History_Type_0143,
	mouse_fur: History_Type_0114,
	mouse_pattern: History_Type_0115,
	mouse_headgear: History_Type_0113,
	mouse_scarf_enabled: bool,
	mouse_scarf_color: History_Type_0148,
	mouse_scarf_rotation: f32,
	mouse_scarf_angular_velocity: f32,
}

// fixture-history-id: adriatic:src.Greek_Placement
History_Type_0112 :: struct {
	asset_index: int,
	x: f32,
	z: f32,
	base_y: f32,
	rotation: f32,
	scale: f32,
}

// fixture-history-id: adriatic:src.Mouse_Accessory
History_Type_0113 :: enum int {
	None = 0,
	Goggles = 1,
	Flower = 2,
	Acorn_Cap = 3,
	Bottle_Cap = 4,
	Paper_Boat = 5,
	Chef_Hat = 6,
	Ushanka = 7,
	Beret = 8,
	Alpine_Hat = 9,
	Flat_Cap = 10,
}

// fixture-history-id: adriatic:src.Mouse_Fur
History_Type_0114 :: enum int {
	Chestnut = 0,
	Silver = 1,
	Cream = 2,
	Soot = 3,
	Russet = 4,
	White = 5,
}

// fixture-history-id: adriatic:src.Mouse_Fur_Pattern
History_Type_0115 :: enum int {
	Solid = 0,
	Pale_Belly = 1,
	Hooded = 2,
	Piebald = 3,
	Dorsal_Stripe = 4,
	Masked = 5,
}

// fixture-history-id: adriatic:src.Particle_CPU_Tweak
History_Type_0116 :: struct {
	spawn_rate: f32,
	origin_radius: f32,
	radial_speed: f32,
	radial_speed_variation: f32,
	lift_speed: f32,
	lift_speed_variation: f32,
	lifetime: f32,
	lifetime_variation: f32,
	size: f32,
	size_variation: f32,
	gravity: f32,
}

// fixture-history-id: adriatic:src.Particle_GPU_Tweak
History_Type_0117 :: struct {
	center: [3]f32,
	radius_min: f32,
	radius_range: f32,
	cycle_rate_min: f32,
	cycle_rate_range: f32,
	drift: f32,
	size_min: f32,
	size_range: f32,
	fade: f32,
	count: int,
	color_start: [3]f32,
	color_end: [3]f32,
}

// fixture-history-id: adriatic:src.Particle_Tweak
History_Type_0118 :: struct {
	cpu_seed: u32,
	vehicle_seed: u32,
	wing_seed: u32,
	cpu: History_Type_0116,
	vehicle: History_Type_0119,
	wing: History_Type_0120,
	gpu: History_Type_0117,
}

// fixture-history-id: adriatic:src.Particle_Vehicle_Tweak
History_Type_0119 :: struct {
	dust_spawn_rate: f32,
	dust_speed_divisor: f32,
	dust_steering_divisor: f32,
	dust_handbrake_bonus: f32,
	dust_max_intensity: f32,
	dust_spawn_threshold: f32,
	dust_contact_spread: f32,
	dust_height: f32,
	dust_radial_speed: f32,
	dust_intensity_speed: f32,
	dust_lift: f32,
	dust_lift_variation: f32,
	dust_lifetime: f32,
	dust_lifetime_variation: f32,
	dust_size: f32,
	dust_intensity_size: f32,
	dust_lift_size: f32,
	dust_gravity: f32,
}

// fixture-history-id: adriatic:src.Particle_Wing_Tweak
History_Type_0120 :: struct {
	airspeed_start: f32,
	airspeed_range: f32,
	wind_strength: f32,
	spawn_rate: f32,
	forward_speed: f32,
	forward_jitter: f32,
	wind_velocity: f32,
	vertical_jitter: f32,
	lifetime: f32,
	lifetime_variation: f32,
	wind_lifetime: f32,
	size: f32,
	strength_size: f32,
	wind_size: f32,
	curve: f32,
	curve_variation: f32,
	gravity: f32,
}

// fixture-history-id: adriatic:src.Player_Animation_Tweak
History_Type_0121 :: struct {
	stride_radians_per_meter: f32,
	trot_stride_radians_per_meter: f32,
	bound_stride_radians_per_meter: f32,
	walk_full_speed: f32,
	trot_full_speed: f32,
	bound_start_speed: f32,
	bound_full_speed: f32,
	vertical_full_speed: f32,
	locomotion_blend_rate: f32,
	airborne_blend_rate: f32,
	vertical_blend_rate: f32,
	turn_blend_rate: f32,
	brake_blend_rate: f32,
	turn_lean_radians: f32,
	turn_spine_offset: f32,
	turn_paw_offset: f32,
	run_body_lift: f32,
	scurry_lean_radians: f32,
	scurry_acceleration_lean: f32,
	scurry_compression: f32,
	scurry_spring_stiffness: f32,
	scurry_spring_damping: f32,
	brake_compression: f32,
	tail_counterbalance: f32,
	slope_alignment: f32,
}

// fixture-history-id: adriatic:src.Presentation_Tweak
History_Type_0122 :: struct {
	terrain_water: [4]f32,
	terrain_sand: [4]f32,
	terrain_soil: [4]f32,
	terrain_grass: [4]f32,
	painted_threshold: f32,
	sand_start: f32,
	land_blend: f32,
	grass_start: f32,
	grass_blend: f32,
	light_direction: [3]f32,
	shade_base: f32,
	shade_strength: f32,
	shade_min: f32,
	shade_max: f32,
	height_shade: f32,
}

// fixture-history-id: adriatic:src.Settlement_Acceptance_Failure
History_Type_0123 :: enum int {
	None = 0,
	Capacity = 1,
	Wide_Route_Share = 2,
	Required_Route = 3,
	Disconnected_Anchors = 4,
	Route_Grade = 5,
	Submerged_Route = 6,
	Submerged_Site = 7,
	Missing_Buildings = 8,
	Insufficient_Buildings = 9,
	Missing_Village_Program = 10,
	Missing_Blocks = 11,
	Fabric_Form = 12,
	Height_Band = 13,
	Height_Outlier = 14,
	Landmark_Count = 15,
	Park_Count = 16,
}

// fixture-history-id: adriatic:src.Settlement_Block
History_Type_0124 :: struct {
	center: [2]f32,
	corners: [8][2]f32,
	corner_count: int,
	short_side: f32,
	long_side: f32,
	area: f32,
	irregularity: f32,
	tissue: History_Type_0141,
}

// fixture-history-id: adriatic:src.Settlement_Building_Purpose
History_Type_0125 :: enum u8 {
	Dwelling = 0,
	Farmstead = 1,
	Barn_Granary = 2,
	Workshop = 3,
	Inn_Shop = 4,
	Mill = 5,
	Fishery = 6,
	Storehouse = 7,
}

// fixture-history-id: adriatic:src.Settlement_Landmark_Kind
History_Type_0126 :: enum u8 {
	Campanile = 0,
	Palace_Loggia = 1,
	Church = 2,
	Monastery = 3,
	Fortress_Gate = 4,
	Harbor_Office = 5,
	Market_Hall = 6,
	Cycladic_Bell = 7,
}

// fixture-history-id: adriatic:src.Settlement_Metrics
History_Type_0127 :: struct {
	route_length: History_Type_0135,
	route_width: History_Type_0135,
	route_grade: History_Type_0135,
	route_length_by_class: [8]History_Type_0135,
	route_width_by_class: [8]History_Type_0135,
	intersection_spacing: History_Type_0135,
	block_short_side: History_Type_0135,
	block_long_side: History_Type_0135,
	block_area: History_Type_0135,
	block_aspect: History_Type_0135,
	block_irregularity: History_Type_0135,
	parcel_frontage: History_Type_0135,
	parcel_depth: History_Type_0135,
	building_height: History_Type_0135,
	building_footprint: History_Type_0135,
	building_floors: History_Type_0135,
	network_density: f32,
	attached_share: f32,
	density_band_count: [3]int,
	wide_route_share: f32,
	minor_route_share: f32,
	fabric_aspect_ratio: f32,
	fabric_quadrants: int,
	landmark_count: int,
	park_count: int,
	rejected_count: int,
	cut_volume: f32,
	fill_volume: f32,
}

// fixture-history-id: adriatic:src.Settlement_Neighborhood
History_Type_0128 :: struct {
	center: [2]f32,
	radius: f32,
	density: f32,
	age: f32,
	suitability: f32,
	tissue: History_Type_0141,
}

// fixture-history-id: adriatic:src.Settlement_Plan
History_Type_0129 :: struct {
	request: History_Type_0132,
	village_reason: History_Type_0146,
	neighborhoods: [96]History_Type_0128,
	neighborhood_count: int,
	macro_cells: [192]History_Type_0128,
	macro_cell_count: int,
	routes: [48]History_Type_0130,
	route_count: int,
	blocks: [128]History_Type_0124,
	block_count: int,
	sites: [256]History_Type_0137,
	site_count: int,
	rejected_sites: [32]History_Type_0137,
	rejected_site_count: int,
	decorative_foliage: [32]History_Type_0087,
	decorative_foliage_count: int,
	terrain_edits: [192]History_Type_0139,
	terrain_edit_count: int,
	ordinary_purposes: [256]History_Type_0125,
	ordinary_purpose_count: int,
	metrics: History_Type_0127,
	acceptance_failure: History_Type_0123,
	valid: bool,
}

// fixture-history-id: adriatic:src.Settlement_Planned_Route
History_Type_0130 :: struct {
	geometry: History_Type_0133,
	class: History_Type_0134,
	width: f32,
	shoulder: f32,
	pavement: History_Type_0069,
	required: bool,
	drivable: bool,
	average_grade: f32,
	maximum_grade: f32,
}

// fixture-history-id: adriatic:src.Settlement_Region
History_Type_0131 :: enum int {
	Adriatic = 0,
	Aegean = 1,
}

// fixture-history-id: adriatic:src.Settlement_Request
History_Type_0132 :: struct {
	region: History_Type_0131,
	scale: History_Type_0136,
	seed: u32,
	center: [2]f32,
	radius: f32,
}

// fixture-history-id: adriatic:src.Settlement_Route
History_Type_0133 :: struct {
	points: [12][2]f32,
	count: int,
}

// fixture-history-id: adriatic:src.Settlement_Route_Class
History_Type_0134 :: enum u8 {
	Civic_Spine = 0,
	Connector = 1,
	Street = 2,
	Lane = 3,
	Alley = 4,
	Stair = 5,
	Waterfront = 6,
	Ridge = 7,
}

// fixture-history-id: adriatic:src.Settlement_Scalar_Stats
History_Type_0135 :: struct {
	count: int,
	min: f32,
	p10: f32,
	median: f32,
	mean: f32,
	p90: f32,
	max: f32,
}

// fixture-history-id: adriatic:src.Settlement_Scale
History_Type_0136 :: enum int {
	City = 0,
	Town = 1,
	Village = 2,
}

// fixture-history-id: adriatic:src.Settlement_Site
History_Type_0137 :: struct {
	structure: History_Type_0087,
	parcel: History_Type_0002,
	kind: History_Type_0138,
	tissue: History_Type_0141,
	density: f32,
	attached: bool,
	accepted: bool,
	landmark_kind: History_Type_0126,
	purpose: History_Type_0125,
}

// fixture-history-id: adriatic:src.Settlement_Site_Kind
History_Type_0138 :: enum u8 {
	Ordinary = 0,
	Landmark = 1,
	Park = 2,
	Rejected = 3,
}

// fixture-history-id: adriatic:src.Settlement_Terrain_Edit
History_Type_0139 :: struct {
	kind: History_Type_0140,
	center: [2]f32,
	half_extent: [2]f32,
	target_height: f32,
	feather: f32,
	cut_volume: f32,
	fill_volume: f32,
}

// fixture-history-id: adriatic:src.Settlement_Terrain_Edit_Kind
History_Type_0140 :: enum u8 {
	Road_Corridor = 0,
	Building_Pad = 1,
	Plaza = 2,
	Neighborhood_Terrace = 3,
	Retaining_Edge = 4,
}

// fixture-history-id: adriatic:src.Settlement_Tissue
History_Type_0141 :: enum u8 {
	Venetian_Mercantile = 0,
	Dalmatian_Planned = 1,
	Hillside_Accretion = 2,
	Harbor = 3,
	Later_Extension = 4,
	Fortified_Precinct = 5,
	Cycladic_Accretion = 6,
	Contour_Terrace = 7,
	Church_Cluster = 8,
}

// fixture-history-id: adriatic:src.Terrain_Tweak
History_Type_0142 :: struct {
	tool: History_Type_0088,
	radius: f32,
	strength: f32,
	hardness: f32,
	sea_level: f32,
}

// fixture-history-id: adriatic:src.Tweak_State
History_Type_0143 :: struct {
	terrain: History_Type_0142,
	atmosphere: History_Type_0004,
	player: History_Type_0093,
	player_animation: History_Type_0121,
	player_tail: History_Type_0048,
	camera: History_Type_0107,
	world: History_Type_0147,
	particles: History_Type_0118,
	car: History_Type_0100,
	car_vehicle: History_Type_0145,
	postale_airframe: History_Type_0024,
	postale_runtime: History_Type_0027,
	postale_tuning: History_Type_0062,
	postale_vehicle: History_Type_0145,
	presentation: History_Type_0122,
}

// fixture-history-id: adriatic:src.Vehicle_Paint_Tool
History_Type_0144 :: enum u8 {
	Brush = 0,
	Bucket = 1,
	Shape = 2,
	Blend = 3,
	Gradient = 4,
	Pattern = 5,
	Strip = 6,
	Shade = 7,
}

// fixture-history-id: adriatic:src.Vehicle_Tweak
History_Type_0145 :: struct {
	interaction_radius: f32,
	exit_distance: f32,
	locked: bool,
}

// fixture-history-id: adriatic:src.Village_Reason
History_Type_0146 :: enum u8 {
	Route_Stop = 0,
	Agricultural_Terrace = 1,
	Harbor_Fishery = 2,
	Upland_Pastoral = 3,
}

// fixture-history-id: adriatic:src.World_Tweak
History_Type_0147 :: struct {
	far_clip: f32,
	fog_start: f32,
	fog_end: f32,
	map_ocean_extent: f32,
	map_ocean_divisions: int,
	editor_ocean_extent: f32,
	editor_ocean_divisions: int,
	map_ocean_depth: f32,
	editor_ocean_depth: f32,
}

// fixture-history-id: zelda_engine:canvas2d.Color
History_Type_0148 :: History_Type_0149

// fixture-history-id: zelda_engine:render2d.Color
History_Type_0149 :: struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,
}

