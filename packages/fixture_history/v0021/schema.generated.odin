// Code generated from immutable fixture history. DO NOT EDIT.
// fixture-history-format-version: 1
// fixture-history-schema-version: 21
// fixture-history-manifest-sha256: 6608496024394758b33bbf4d7de14f94eaffc87e9212c40f7deba89cf9720a9e
package fixture_v0021

FIXTURE_SCHEMA_VERSION :: 21

// fixture-history-id: adriatic:packages/architecture.City_Alley
History_Type_0000 :: struct {
	start_x: f32,
	start_z: f32,
	end_x: f32,
	end_z: f32,
	half_width: f32,
	household_demand: u16,
	start_terminal: History_Type_0001,
	end_terminal: History_Type_0001,
	curve_control_from: [2]f32,
	curve_control_to: [2]f32,
	curve_ready: bool,
}

// fixture-history-id: adriatic:packages/architecture.City_Alley_Terminal
History_Type_0001 :: enum u8 {
	None = 0,
	Door = 1,
	Road = 2,
	Public_Space = 3,
}

// fixture-history-id: adriatic:packages/architecture.City_Lamp
History_Type_0002 :: struct {
	x: f32,
	z: f32,
	yaw: f32,
}

// fixture-history-id: adriatic:packages/architecture.City_Parcel
History_Type_0003 :: struct {
	corners: [4][2]f32,
	frontage_width: f32,
	depth: f32,
	density: f32,
	seed: u32,
	attached: bool,
	alley_frontage: bool,
}

// fixture-history-id: adriatic:packages/architecture.City_Plan
History_Type_0004 :: struct {
	structures: [dynamic]History_Type_0077,
	count: int,
	parcels: [dynamic]History_Type_0003,
	parcel_count: int,
	alleys: [dynamic]History_Type_0000,
	alley_count: int,
	lamps: [dynamic]History_Type_0002,
	lamp_count: int,
}

// fixture-history-id: adriatic:packages/atmosphere.Atmosphere
History_Type_0005 :: struct {
	seed: u32,
	world_minutes: f32,
	world_days: f32,
	lunar_days: f32,
	front_seconds: f32,
	weather: History_Type_0011,
	override: History_Type_0010,
	paused: bool,
	schedule: History_Type_0008,
	climate: History_Type_0007,
}

// fixture-history-id: adriatic:packages/atmosphere.Climate_Regime
History_Type_0006 :: enum u8 {
	Maestral = 0,
	Bura_Clear = 1,
	Bura_Storm = 2,
	Jugo = 3,
	Calm_Humid = 4,
	Post_Front = 5,
}

// fixture-history-id: adriatic:packages/atmosphere.Climate_State
History_Type_0007 :: struct {
	initialized: bool,
	rng_state: u32,
	current: History_Type_0006,
	next: History_Type_0006,
	elapsed_seconds: f32,
	transition_start_seconds: f32,
	transition_end_seconds: f32,
}

// fixture-history-id: adriatic:packages/atmosphere.Front_Schedule
History_Type_0008 :: struct {
	initialized: bool,
	rng_state: u32,
	elapsed_seconds: f32,
	next_event_seconds: f32,
	event_serial: u32,
	front: History_Type_0009,
}

// fixture-history-id: adriatic:packages/atmosphere.Front_State
History_Type_0009 :: struct {
	active: bool,
	event_id: u32,
	seed: u32,
	start_seconds: f32,
	end_seconds: f32,
	origin: [2]f32,
	direction: [2]f32,
	speed: f32,
	width: f32,
	intensity: f32,
	gustiness: f32,
	rainfall: f32,
	visibility_loss: f32,
	cell_scale: f32,
	cell_phase: f32,
}

// fixture-history-id: adriatic:packages/atmosphere.Weather_Preset
History_Type_0010 :: enum int {
	Automatic = 0,
	Clear = 1,
	Windy = 2,
	Storm = 3,
}

// fixture-history-id: adriatic:packages/atmosphere.Weather_State
History_Type_0011 :: struct {
	cloud_cover: f32,
	precipitation: f32,
	haze: f32,
	severity: f32,
	wind: [2]f32,
}

// fixture-history-id: adriatic:packages/boats.Agent
History_Type_0012 :: struct {
	class: History_Type_0014,
	position: History_Type_0017,
	velocity: History_Type_0017,
	yaw: f32,
	speed: f32,
	throttle: f32,
	behavior: History_Type_0013,
	route: [8]History_Type_0017,
	route_count: int,
	route_index: int,
	schedule: [5]History_Type_0015,
	schedule_count: int,
	loiter_center: History_Type_0017,
	loiter_radius: f32,
	loiter_phase: f32,
	mooring_position: History_Type_0017,
	mooring_yaw: f32,
	wake: [48]History_Type_0018,
	wake_count: int,
	wake_distance: f32,
}

// fixture-history-id: adriatic:packages/boats.Behavior
History_Type_0013 :: enum u8 {
	Transit = 0,
	Patrol = 1,
	Loiter = 2,
	Moored = 3,
}

// fixture-history-id: adriatic:packages/boats.Class
History_Type_0014 :: enum u8 {
	Motor = 0,
	Sail = 1,
	Fishing = 2,
	Tug = 3,
	Dinghy = 4,
}

// fixture-history-id: adriatic:packages/boats.Schedule_Entry
History_Type_0015 :: struct {
	start_minutes: f32,
	end_minutes: f32,
	behavior: History_Type_0013,
	speed_scale: f32,
}

// fixture-history-id: adriatic:packages/boats.Traffic
History_Type_0016 :: struct {
	agents: [32]History_Type_0012,
	count: int,
	clock: f32,
}

// fixture-history-id: adriatic:packages/boats.Vec2
History_Type_0017 :: [2]f32

// fixture-history-id: adriatic:packages/boats.Wake_Sample
History_Type_0018 :: struct {
	position: History_Type_0017,
	direction: History_Type_0017,
	age: f32,
	lifetime: f32,
	width: f32,
	strength: f32,
}

// fixture-history-id: adriatic:packages/buildings.Archetype
History_Type_0019 :: enum u8 {
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
	Mixed_Use_Dwelling = 18,
	Post_Office = 19,
	Lighthouse = 20,
	Clinic = 21,
}

// fixture-history-id: adriatic:packages/buildings.Identity
History_Type_0020 :: struct {
	archetype: History_Type_0019,
	purpose: History_Type_0022,
	region: History_Type_0023,
	landmark_kind: History_Type_0021,
}

// fixture-history-id: adriatic:packages/buildings.Landmark_Kind
History_Type_0021 :: enum u8 {
	None = 0,
	Campanile = 1,
	Palace_Loggia = 2,
	Church = 3,
	Monastery = 4,
	Fortress_Gate = 5,
	Harbor_Office = 6,
	Market_Hall = 7,
	Cycladic_Bell = 8,
	Post_Office = 9,
	Lighthouse = 10,
	Clinic = 11,
}

// fixture-history-id: adriatic:packages/buildings.Purpose
History_Type_0022 :: enum u8 {
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
History_Type_0023 :: enum u8 {
	Adriatic = 0,
	Aegean = 1,
}

// fixture-history-id: adriatic:packages/chase_camera.State
History_Type_0024 :: struct {
	pose: History_Type_0080,
	base_pose: History_Type_0080,
	orbit_yaw: f32,
	orbit_pitch: f32,
	focal_length: f32,
	shake_phase: f32,
	shake_intensity: f32,
	previous_target_position: History_Type_0034,
	initialized: bool,
}

// fixture-history-id: adriatic:packages/flight.Ace_Edge_State
History_Type_0025 :: enum int {
	Free = 0,
	Warning = 1,
	Hang = 2,
	Break = 3,
	Recovery = 4,
}

// fixture-history-id: adriatic:packages/flight.Ace_Runtime
History_Type_0026 :: struct {
	energy: f32,
	edge_state: History_Type_0025,
	edge_seconds: f32,
}

// fixture-history-id: adriatic:packages/flight.Ace_Tuning
History_Type_0027 :: struct {
	pace: f32,
	punch: f32,
	coast: f32,
	brake: f32,
	roll_snap: f32,
	pull_strength: f32,
	rudder_bite: f32,
	weight: f32,
	settle: f32,
	air_grip: f32,
	drift: f32,
	turn_hold: f32,
	climb_generosity: f32,
	dive_payoff: f32,
	hang_time: f32,
	break_drama: f32,
	recovery_punch: f32,
	low_speed_authority: f32,
	steadiness: f32,
	line_hold: f32,
	commitment: f32,
	exit_catch: f32,
}

// fixture-history-id: adriatic:packages/flight.Airframe
History_Type_0028 :: struct {
	flight_layout: u8,
	mass_kg: f32,
	maximum_gross_mass_kg: f32,
	wing_area: f32,
	lift_scale: f32,
	drag_scale: f32,
	parasitic_drag_area: f32,
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
History_Type_0029 :: struct {
	forward: History_Type_0034,
	up: History_Type_0034,
	right: History_Type_0034,
}

// fixture-history-id: adriatic:packages/flight.Body_State
History_Type_0030 :: struct {
	position: History_Type_0034,
	velocity: History_Type_0034,
	angular_velocity_world: History_Type_0034,
	orientation: quaternion128,
}

// fixture-history-id: adriatic:packages/flight.Runtime
History_Type_0031 :: struct {
	engine_output: f32,
	control_authority: f32,
	drag_multiplier: f32,
	controls_damaged: bool,
}

// fixture-history-id: adriatic:packages/flight.Tri_Rotor_Airframe
History_Type_0032 :: struct {
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
History_Type_0033 :: struct {
	left_engine_output: f32,
	right_engine_output: f32,
	rear_engine_output: f32,
	auto_level: bool,
	ground_distance: f32,
}

// fixture-history-id: adriatic:packages/flight.Vec3
History_Type_0034 :: [3]f32

// fixture-history-id: adriatic:packages/libellula.Runtime
History_Type_0035 :: struct {
	body: History_Type_0030,
	vehicle: History_Type_0098,
	airframe: History_Type_0032,
	flight_runtime: History_Type_0033,
	tuning: History_Type_0036,
	spawn_position: History_Type_0034,
	spawn_orientation: quaternion128,
	throttle: f32,
	pitch: f32,
	roll: f32,
	yaw: f32,
	rotor_turns: History_Type_0034,
	grounded: bool,
	was_grounded: bool,
	crashed: bool,
	lift_active: bool,
}

// fixture-history-id: adriatic:packages/libellula.Tuning
History_Type_0036 :: struct {
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

// fixture-history-id: adriatic:packages/mouse_tail.Config
History_Type_0037 :: struct {
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

// fixture-history-id: adriatic:packages/particles.Dust_Surface
History_Type_0038 :: enum u8 {
	Grass = 0,
	Asphalt = 1,
	Gravel = 2,
	Cobblestone = 3,
	Dirt = 4,
	Sand = 5,
}

// fixture-history-id: adriatic:packages/particles.Particle
History_Type_0039 :: struct {
	position: History_Type_0041,
	velocity: History_Type_0041,
	life: f32,
	max_life: f32,
	size: f32,
	seed: u32,
}

// fixture-history-id: adriatic:packages/particles.Petal_Effects
History_Type_0040 :: struct {
	particles: [192]History_Type_0039,
	count: int,
	spawn: f32,
	seed: u32,
}

// fixture-history-id: adriatic:packages/particles.Vec3
History_Type_0041 :: struct {
	x: f32,
	y: f32,
	z: f32,
}

// fixture-history-id: adriatic:packages/particles.Vehicle_Effects
History_Type_0042 :: struct {
	dust: [256]History_Type_0043,
	dust_count: int,
	dust_spawn: f32,
	seed: u32,
}

// fixture-history-id: adriatic:packages/particles.Vehicle_Particle
History_Type_0043 :: struct {
	position: History_Type_0041,
	velocity: History_Type_0041,
	life: f32,
	max_life: f32,
	size: f32,
	seed: u32,
	surface: History_Type_0038,
}

// fixture-history-id: adriatic:packages/particles.Wing_Trail_Particle
History_Type_0044 :: struct {
	position: History_Type_0041,
	velocity: History_Type_0041,
	life: f32,
	max_life: f32,
	size: f32,
	seed: u32,
	side: u8,
	curve: f32,
}

// fixture-history-id: adriatic:packages/particles.Wing_Trails
History_Type_0045 :: struct {
	particles: [576]History_Type_0044,
	count: int,
	spawn: f32,
	seed: u32,
}

// fixture-history-id: adriatic:packages/player_mail.State
History_Type_0046 :: struct {
	received: [3]bool,
	read: [3]bool,
}

// fixture-history-id: adriatic:packages/postale.Flight_Model
History_Type_0047 :: enum int {
	Current_Aero = 0,
	Ace_Arcade = 1,
}

// fixture-history-id: adriatic:packages/postale.Landing_Impact
History_Type_0048 :: struct {
	outcome: History_Type_0049,
	sink_speed: f32,
	weight_force: f32,
	impact_force: f32,
	load_factor: f32,
	damage: f32,
}

// fixture-history-id: adriatic:packages/postale.Landing_Outcome
History_Type_0049 :: enum int {
	None = 0,
	Smooth = 1,
	Landed = 2,
	Hard_Landing = 3,
	Crash = 4,
}

// fixture-history-id: adriatic:packages/postale.Runtime
History_Type_0050 :: struct {
	body: History_Type_0030,
	vehicle: History_Type_0098,
	airframe: History_Type_0028,
	flight_runtime: History_Type_0031,
	flight_model: History_Type_0047,
	ace_tuning: History_Type_0027,
	ace_runtime: History_Type_0026,
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
	ground_pitch_radians: f32,
	ground_brake_amount: f32,
	gear_compression: f32,
	gear_force: f32,
	structural_damage: f32,
	last_landing: History_Type_0048,
	landing_feedback_seconds: f32,
	landing_intent_seconds: f32,
	landing_intent: bool,
	spawn_position: History_Type_0034,
	spawn_orientation: quaternion128,
	tuning: History_Type_0051,
}

// fixture-history-id: adriatic:packages/postale.Tuning
History_Type_0051 :: struct {
	ground_clearance: f32,
	safe_bank_radians: f32,
	gear_compression_distance: f32,
	gear_damping_ratio: f32,
	smooth_landing_load: f32,
	hard_landing_load: f32,
	ultimate_landing_load: f32,
	safe_exit_speed: f32,
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
	propeller_base_rate: f32,
	propeller_throttle_rate: f32,
}

// fixture-history-id: adriatic:packages/quest.Node_ID
History_Type_0052 :: distinct int

// fixture-history-id: adriatic:packages/quest.State
History_Type_0053 :: struct {
	definition_id: string,
	node_count: int,
	statuses: [128]History_Type_0054,
	completion_counts: [128]int,
	activated_at: [128]u64,
	completed_at: [128]u64,
	revision: u64,
}

// fixture-history-id: adriatic:packages/quest.Status
History_Type_0054 :: enum u8 {
	Locked = 0,
	Available = 1,
	Active = 2,
	Completed = 3,
}

// fixture-history-id: adriatic:packages/roads.Pavement
History_Type_0055 :: enum u8 {
	Asphalt = 0,
	Gravel = 1,
	Cobblestone = 2,
	Dirt = 3,
	Steps = 4,
}

// fixture-history-id: adriatic:packages/rondine.Runtime
History_Type_0056 :: struct {
	body: History_Type_0030,
	vehicle: History_Type_0098,
	tuning: History_Type_0058,
	telemetry: History_Type_0057,
	spawn_position: History_Type_0034,
	spawn_basis: History_Type_0029,
	throttle: f32,
	propeller_turns: f32,
	steering: f32,
	target_height: f32,
	grounded: bool,
	crashed: bool,
	wake: [96]History_Type_0059,
	wake_count: int,
	wake_distance: f32,
	wake_serial: u32,
	drift_kick: f32,
	hookup_kick: f32,
	surface_impact: f32,
	surface_release: f32,
	surge_intensity: f32,
	brake_intensity: f32,
	drift_transition: f32,
	slip_side: f32,
	kick_marker_armed: bool,
	impact_marker_armed: bool,
	release_marker_armed: bool,
	transition_marker_armed: bool,
}

// fixture-history-id: adriatic:packages/rondine.Telemetry
History_Type_0057 :: struct {
	speed: f32,
	forward_speed: f32,
	lateral_speed: f32,
	acceleration: f32,
	surge_intensity: f32,
	brake_intensity: f32,
	drift_transition: f32,
	slip: f32,
	drift_intensity: f32,
	countersteer: f32,
	drift_kick: f32,
	hookup_kick: f32,
	surface_impact: f32,
	surface_release: f32,
	turn_rate: f32,
	height: f32,
	wake_intensity: f32,
	spray_intensity: f32,
}

// fixture-history-id: adriatic:packages/rondine.Tuning
History_Type_0058 :: struct {
	thrust_acceleration: f32,
	maximum_speed: f32,
	cruise_speed: f32,
	takeoff_speed: f32,
	throttle_up_rate: f32,
	throttle_down_rate: f32,
	turn_rate: f32,
	yaw_rate: f32,
	lateral_grip: f32,
	height_gain: f32,
	height_damping: f32,
}

// fixture-history-id: adriatic:packages/rondine.Wake_Sample
History_Type_0059 :: struct {
	serial: u32,
	position: History_Type_0034,
	forward: History_Type_0034,
	right: History_Type_0034,
	age: f32,
	lifetime: f32,
	strength: f32,
	slip: f32,
	turn: f32,
	countersteer: f32,
	kick: f32,
	hookup: f32,
	impact: f32,
	release: f32,
	transition: f32,
}

// fixture-history-id: adriatic:packages/story.Airfield_Errand_Stage
History_Type_0060 :: enum int {
	Not_Offered = 0,
	Westbound = 1,
	Eastbound = 2,
	Completed = 3,
}

// fixture-history-id: adriatic:packages/story.Cargo_Care
History_Type_0061 :: enum int {
	Unchosen = 0,
	Orderly = 1,
	Expressive = 2,
}

// fixture-history-id: adriatic:packages/story.Delivery
History_Type_0062 :: struct {
	active: bool,
	kind: History_Type_0063,
	from: History_Type_0066,
	to: History_Type_0066,
	origin: History_Type_0064,
	destination: History_Type_0064,
	subject: string,
	care: History_Type_0061,
}

// fixture-history-id: adriatic:packages/story.Delivery_Kind
History_Type_0063 :: enum int {
	None = 0,
	First_Letter = 1,
	First_Reply = 2,
	Regatta_Invitation = 3,
	Regatta_Acceptance = 4,
	Repeat_Eastbound = 5,
	Repeat_Westbound = 6,
	Clinic_Medicine = 7,
	Clinic_Linens = 8,
	Clinic_Water = 9,
}

// fixture-history-id: adriatic:packages/story.Island
History_Type_0064 :: enum int {
	West = 0,
	East = 1,
}

// fixture-history-id: adriatic:packages/story.Repair_Stage
History_Type_0065 :: enum int {
	Not_Seen = 0,
	Crash_Reported = 1,
	Diagnosed = 2,
	Patched = 3,
	Repaired = 4,
}

// fixture-history-id: adriatic:packages/story.Resident
History_Type_0066 :: enum int {
	Marta = 0,
	Gerta = 1,
	Niko = 2,
	Iva = 3,
	Bojan = 4,
	Zora = 5,
	Vesna = 6,
	Petar = 7,
	Anica = 8,
	Toma = 9,
	Lena = 10,
	Mirna = 11,
}

// fixture-history-id: adriatic:packages/story.Romance_Stage
History_Type_0067 :: enum int {
	Unintroduced = 0,
	First_Letter = 1,
	Corresponding = 2,
	Invitation = 3,
	Meeting = 4,
	Together = 5,
}

// fixture-history-id: adriatic:packages/story.State
History_Type_0068 :: struct {
	quest: History_Type_0053,
	romance: History_Type_0067,
	repair: History_Type_0065,
	airfield_errand: History_Type_0060,
	delivery: History_Type_0062,
	completed_deliveries: int,
	repeat_deliveries: int,
	stamps_earned: int,
	bonus_stamps: int,
	careful_deliveries: int,
	expressive_deliveries: int,
	friendship_points: int,
	magneto_wrapped: bool,
	weather_reading_done: bool,
	medicine_delivered: bool,
	linens_delivered: bool,
	water_delivered: bool,
	has_weather_briefing: bool,
	has_clinic_satchel: bool,
	has_dry_wrap: bool,
	has_recovery_kit: bool,
	has_wing_patch: bool,
	tarot_readings: int,
	tarot_seed: u32,
	tarot_last_moment: u32,
	tarot_layout: History_Type_0070,
	clinic_visits: int,
	last_clinic_visit_was_tumble: bool,
	resident_action_seen: [History_Type_0066]u64,
}

// fixture-history-id: adriatic:packages/tarot.Card
History_Type_0069 :: distinct u8

// fixture-history-id: adriatic:packages/tarot.Layout
History_Type_0070 :: struct {
	spread: History_Type_0073,
	placements: [10]History_Type_0072,
	count: int,
	seed: u32,
}

// fixture-history-id: adriatic:packages/tarot.Orientation
History_Type_0071 :: enum int {
	Upright = 0,
	Reversed = 1,
}

// fixture-history-id: adriatic:packages/tarot.Placement
History_Type_0072 :: struct {
	card: History_Type_0069,
	orientation: History_Type_0071,
	position: string,
}

// fixture-history-id: adriatic:packages/tarot.Spread
History_Type_0073 :: enum int {
	Single = 0,
	Three_Card = 1,
	Celtic_Cross = 2,
}

// fixture-history-id: adriatic:packages/terrain.Cliff_Elevation_Mode
History_Type_0074 :: enum int {
	Raise = 0,
	Lower = 1,
	Split = 2,
}

// fixture-history-id: adriatic:packages/terrain.Entrance_Side
History_Type_0075 :: enum u8 {
	Front = 0,
	Right = 1,
	Rear = 2,
	Left = 3,
}

// fixture-history-id: adriatic:packages/terrain.Formation_Kind
History_Type_0076 :: enum int {
	Box = 0,
	Rock = 1,
	Spire = 2,
	Mountain = 3,
	Ridge = 4,
	Cliff = 5,
	Foliage = 6,
	Architecture = 7,
	Ruins = 8,
}

// fixture-history-id: adriatic:packages/terrain.Structure
History_Type_0077 :: struct {
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
	kind: History_Type_0076,
	entrance_side: History_Type_0075,
	seed: u32,
	building: History_Type_0020,
}

// fixture-history-id: adriatic:packages/terrain.Tool
History_Type_0078 :: enum int {
	Raise = 0,
	Smooth = 1,
	Paint = 2,
	Structure = 3,
}

// fixture-history-id: adriatic:packages/third_person.Camera
History_Type_0079 :: struct {
	yaw_radians: f32,
	pitch_radians: f32,
	distance: f32,
	height: f32,
}

// fixture-history-id: adriatic:packages/third_person.Camera_Pose
History_Type_0080 :: struct {
	position: History_Type_0085,
	target: History_Type_0085,
}

// fixture-history-id: adriatic:packages/third_person.Camera_Slot
History_Type_0081 :: enum u8 {
	Player = 0,
	Inspection = 1,
	Cutaway = 2,
	Count = 3,
}

// fixture-history-id: adriatic:packages/third_person.Camera_System
History_Type_0082 :: struct {
	poses: [3]History_Type_0080,
	active: History_Type_0081,
}

// fixture-history-id: adriatic:packages/third_person.Config
History_Type_0083 :: struct {
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
History_Type_0084 :: struct {
	position: History_Type_0085,
	velocity: History_Type_0085,
	facing_yaw_radians: f32,
	grounded: bool,
	turn_amount: f32,
	brake_amount: f32,
	ground_normal: History_Type_0085,
	running: bool,
	drifting: bool,
	drift_charge: f32,
	boost_seconds: f32,
}

// fixture-history-id: adriatic:packages/third_person.Vec3
History_Type_0085 :: [3]f32

// fixture-history-id: adriatic:packages/vehicles.Aircraft_Fleet
History_Type_0086 :: struct {
	slots: [8]History_Type_0088,
	count: int,
	active: History_Type_0087,
}

// fixture-history-id: adriatic:packages/vehicles.Aircraft_Kind
History_Type_0087 :: enum u8 {
	Postale = 0,
	Libellula = 1,
	Libellula_Mk2 = 2,
	Rondine = 3,
}

// fixture-history-id: adriatic:packages/vehicles.Aircraft_Slot
History_Type_0088 :: struct {
	kind: History_Type_0087,
	name: string,
	available: bool,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Drive_State
History_Type_0089 :: struct {
	velocity: History_Type_0085,
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
	racer: History_Type_0092,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Drive_Tune
History_Type_0090 :: struct {
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
	racer: History_Type_0093,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Handling_Model
History_Type_0091 :: enum int {
	Current_Physics = 0,
	Racer_Arcade = 1,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Racer_Runtime
History_Type_0092 :: struct {
	drift_amount: f32,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Racer_Tune
History_Type_0093 :: struct {
	steering_authority_low: f32,
	steering_authority_high: f32,
	drift_min_speed: f32,
	drift_full_speed: f32,
	drift_steering_start: f32,
	drift_steering_full: f32,
	drift_rear_grip: f32,
	drift_slip_ratio: f32,
	drift_engage_response: f32,
	drift_release_response: f32,
	drift_lateral_response: f32,
}

// fixture-history-id: adriatic:packages/vehicles.Car_Trailer_State
History_Type_0094 :: struct {
	velocity: History_Type_0085,
	yaw_rate: f32,
	reaction_force: History_Type_0085,
	body_roll: f32,
	body_pitch: f32,
	wheel_rotation: f32,
}

// fixture-history-id: adriatic:packages/vehicles.Character
History_Type_0095 :: struct {
	position: History_Type_0085,
	facing_yaw_radians: f32,
	mode: History_Type_0097,
}

// fixture-history-id: adriatic:packages/vehicles.Fixture_Occupant
History_Type_0096 :: enum u8 {
	On_Foot = 0,
	Car = 1,
	Postale = 2,
	Libellula = 3,
	Libellula_Mk2 = 4,
	Rondine = 5,
}

// fixture-history-id: adriatic:packages/vehicles.Occupancy_Mode
History_Type_0097 :: enum int {
	On_Foot = 0,
	Driving = 1,
}

// fixture-history-id: adriatic:packages/vehicles.Vehicle
History_Type_0098 :: struct {
	position: History_Type_0085,
	yaw_radians: f32,
	interaction_radius: f32,
	exit_distance: f32,
	locked: bool,
}

// fixture-history-id: adriatic:src.Authoring_Tool
History_Type_0099 :: enum int {
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
	Wreck = 10,
	ClimbingLeaves = 11,
	Roads = 12,
	GreekAssets = 13,
	Obstacles = 14,
}

// fixture-history-id: adriatic:src.Camera_Tweak
History_Type_0100 :: struct {
	editor_camera: History_Type_0079,
	editor_focus: History_Type_0085,
	player_camera: History_Type_0079,
	flight_orbit_yaw: f32,
	flight_orbit_pitch: f32,
}

// fixture-history-id: adriatic:src.Curve_Point
History_Type_0101 :: struct {
	x: f32,
	z: f32,
}

// fixture-history-id: adriatic:src.Dunes_Lab_Config
History_Type_0102 :: struct {
	seed: u32,
	wind_angle: f32,
	vegetation: f32,
}

// fixture-history-id: adriatic:src.Editor_UI_State
History_Type_0103 :: struct {
	left_collapsed: bool,
	inspector_collapsed: bool,
}

// fixture-history-id: adriatic:src.Fixture
Fixture :: struct {
	authoring_tool: History_Type_0099,
	editor_ui: History_Type_0103,
	sdf_obstacles: [64]History_Type_0122,
	sdf_obstacle_count: int,
	sdf_obstacle_selected: int,
	tool: History_Type_0078,
	radius: f32,
	strength: f32,
	hardness: f32,
	structure_selected: int,
	structure_kind: History_Type_0076,
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
	architecture_city_plan: History_Type_0004,
	architecture_brush_shape: History_Type_0124,
	architecture_brush_preset: History_Type_0123,
	architecture_brush_strength: f32,
	architecture_brush_hardness: f32,
	marina_paint_mode: bool,
	marina_brush_radius: f32,
	farm_paint_mode: bool,
	farm_brush_radius: f32,
	farm_brush_yaw: f32,
	wreck_paint_mode: bool,
	wreck_brush_size: f32,
	wreck_brush_yaw: f32,
	climbing_leaf_paint_mode: bool,
	climbing_leaf_brush_radius: f32,
	climbing_leaf_brush_strength: f32,
	climbing_leaf_brush_hardness: f32,
	greek_asset_selected: int,
	greek_asset_rotation: f32,
	greek_asset_scale: f32,
	greek_placement_selected: int,
	greek_placement_mode: bool,
	curve_points: [48]History_Type_0101,
	curve_point_count: int,
	curve_mode: bool,
	curve_cliff_mode: bool,
	curve_width: f32,
	curve_height: f32,
	cliff_elevation_mode: History_Type_0074,
	road_mode: bool,
	road_selected_node: int,
	road_width: f32,
	road_shoulder_width: f32,
	road_pavement: History_Type_0055,
	in_map: bool,
	player: History_Type_0084,
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
	camera: History_Type_0079,
	camera_pose: History_Type_0080,
	cameras: History_Type_0082,
	flight_camera: History_Type_0024,
	editor_camera: History_Type_0079,
	editor_focus: History_Type_0085,
	boat_traffic: History_Type_0016,
	marina_dinghy_borrowed: bool,
	occupant: History_Type_0096,
	pilot: History_Type_0095,
	car: History_Type_0098,
	car_handling_model: History_Type_0091,
	car_drive: History_Type_0089,
	car_trailer: History_Type_0094,
	car_trailer_attached: bool,
	car_trailer_position: History_Type_0085,
	car_trailer_yaw: f32,
	postale: History_Type_0050,
	libellula: History_Type_0035,
	rondine: History_Type_0056,
	aircraft: History_Type_0086,
	postale_visible: bool,
	libellula_visible: bool,
	rondine_visible: bool,
	vehicle_showcase_scene: bool,
	wildflower_lab_scene: bool,
	vehicle_showcase_target: string,
	shadow_lab_scene: bool,
	lab: History_Type_0110,
	settlement_vertical_map: bool,
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
	vehicle_paint_tool: History_Type_0127,
	vehicle_paint_component: int,
	vehicle_paint_component_mask: [5]bool,
	vehicle_paint_saved_postale_position: History_Type_0034,
	vehicle_paint_saved_libellula_position: History_Type_0034,
	vehicle_paint_brush_radius: int,
	vehicle_paint_brush_hardness: f32,
	vehicle_paint_brush_strength: f32,
	vehicle_paint_erase: bool,
	vehicle_paint_symmetry: bool,
	vehicle_paint_components: [5]bool,
	attendant_position: History_Type_0085,
	gerta_position: History_Type_0085,
	story_state: History_Type_0068,
	player_mail: History_Type_0046,
	tracked_quest_node: History_Type_0052,
	quest_tracking_suppressed: bool,
	quest_tracking_revision: u64,
	atmosphere: History_Type_0005,
	vehicle_effects: History_Type_0042,
	wing_trails: History_Type_0045,
	petal_effects: History_Type_0040,
	tweak: History_Type_0126,
	mouse_fur: History_Type_0113,
	mouse_pattern: History_Type_0114,
	mouse_headgear: History_Type_0112,
	mouse_scarf_enabled: bool,
	mouse_scarf_color: History_Type_0130,
	mouse_scarf_rotation: f32,
	mouse_scarf_angular_velocity: f32,
	notes: [64]History_Type_0108,
	note_count: int,
	map_source: History_Type_0106,
}

// fixture-history-id: adriatic:src.Fixture_Map_Sidecar
History_Type_0105 :: struct {
	basename: [128]byte,
	basename_count: int,
	container_version: u16,
	format_version: u32,
	generator_version: u64,
	encoded_sha256: [32]byte,
}

// fixture-history-id: adriatic:src.Fixture_Map_Source
History_Type_0106 :: struct {
	kind: History_Type_0107,
	inline_bytes: [dynamic]u8,
	sidecar: History_Type_0105,
}

// fixture-history-id: adriatic:src.Fixture_Map_Source_Kind
History_Type_0107 :: enum u8 {
	Inline = 0,
	Sidecar = 1,
}

// fixture-history-id: adriatic:src.Fixture_Note
History_Type_0108 :: struct {
	text: [256]u8,
	target: History_Type_0109,
	target_id: u64,
	fallback_position: History_Type_0085,
}

// fixture-history-id: adriatic:src.Fixture_Note_Target
History_Type_0109 :: enum u8 {
	Scene = 0,
	Structure = 1,
}

// fixture-history-id: adriatic:src.Lab_Fixture_State
History_Type_0110 :: struct {
	kind: History_Type_0111,
	dunes: History_Type_0102,
}

// fixture-history-id: adriatic:src.Lab_Kind
History_Type_0111 :: enum u8 {
	None = 0,
	Dunes = 1,
}

// fixture-history-id: adriatic:src.Mouse_Accessory
History_Type_0112 :: enum int {
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
	Sailor_Hat = 11,
}

// fixture-history-id: adriatic:src.Mouse_Fur
History_Type_0113 :: enum int {
	Chestnut = 0,
	Silver = 1,
	Cream = 2,
	Soot = 3,
	Russet = 4,
	White = 5,
}

// fixture-history-id: adriatic:src.Mouse_Fur_Pattern
History_Type_0114 :: enum int {
	Solid = 0,
	Pale_Belly = 1,
	Hooded = 2,
	Piebald = 3,
	Dorsal_Stripe = 4,
	Masked = 5,
}

// fixture-history-id: adriatic:src.Particle_CPU_Tweak
History_Type_0115 :: struct {
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
History_Type_0116 :: struct {
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
History_Type_0117 :: struct {
	cpu_seed: u32,
	vehicle_seed: u32,
	wing_seed: u32,
	cpu: History_Type_0115,
	vehicle: History_Type_0118,
	wing: History_Type_0119,
	gpu: History_Type_0116,
}

// fixture-history-id: adriatic:src.Particle_Vehicle_Tweak
History_Type_0118 :: struct {
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
History_Type_0119 :: struct {
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
History_Type_0120 :: struct {
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
	body_softness_strength: f32,
	body_softness_influence_radius: f32,
	body_softness_volume_return: f32,
	body_softness_stiffness: f32,
	body_softness_damping: f32,
	body_softness_inertial_lag: f32,
	body_softness_max_displacement: f32,
}

// fixture-history-id: adriatic:src.Presentation_Tweak
History_Type_0121 :: struct {
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

// fixture-history-id: adriatic:src.SDF_Torus_Obstacle
History_Type_0122 :: struct {
	position: History_Type_0034,
	rotation: quaternion128,
	scale: History_Type_0034,
	major_radius: f32,
	tube_radius: f32,
	color: [4]u8,
}

// fixture-history-id: adriatic:src.Settlement_Brush_Preset
History_Type_0123 :: enum u8 {
	Small = 0,
	Medium = 1,
	Large = 2,
}

// fixture-history-id: adriatic:src.Settlement_Brush_Shape
History_Type_0124 :: enum u8 {
	Square = 0,
	Rectangle = 1,
	Circle = 2,
	Macaroni = 3,
}

// fixture-history-id: adriatic:src.Terrain_Tweak
History_Type_0125 :: struct {
	tool: History_Type_0078,
	radius: f32,
	strength: f32,
	hardness: f32,
	sea_level: f32,
}

// fixture-history-id: adriatic:src.Tweak_State
History_Type_0126 :: struct {
	terrain: History_Type_0125,
	atmosphere: History_Type_0005,
	player: History_Type_0083,
	player_animation: History_Type_0120,
	player_tail: History_Type_0037,
	camera: History_Type_0100,
	world: History_Type_0129,
	particles: History_Type_0117,
	car: History_Type_0090,
	car_vehicle: History_Type_0128,
	postale_airframe: History_Type_0028,
	postale_runtime: History_Type_0031,
	postale_ace_tuning: History_Type_0027,
	postale_tuning: History_Type_0051,
	postale_vehicle: History_Type_0128,
	presentation: History_Type_0121,
}

// fixture-history-id: adriatic:src.Vehicle_Paint_Tool
History_Type_0127 :: enum u8 {
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
History_Type_0128 :: struct {
	interaction_radius: f32,
	exit_distance: f32,
	locked: bool,
}

// fixture-history-id: adriatic:src.World_Tweak
History_Type_0129 :: struct {
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
History_Type_0130 :: History_Type_0131

// fixture-history-id: zelda_engine:render2d.Color
History_Type_0131 :: struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,
}

