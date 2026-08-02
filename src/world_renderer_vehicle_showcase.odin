package main
import "core:math"

import flight "../packages/flight"
import mouse_gait "../packages/mouse_gait"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

world_vehicle_showcase :: proc(editor: ^Editor) {
    // The showcase is intentionally self-contained: the vehicle is presented
    // against the sky with no island, runway, floor, or town geometry.
    if editor.vehicle_showcase_target == "postale" {
        world_aircraft(editor)
        world_postale_pilot(editor)
    } else if editor.vehicle_showcase_target == "libellula" || editor.vehicle_showcase_target == "libellula-mk2" {
        world_aircraft(editor)
        basis := flight.basis_from_orientation(editor.libellula.body.orientation)
        world_showcase_aircraft_pilot(editor, editor.libellula.body.position, basis)
    } else if editor.vehicle_showcase_target == "rondine" {
        p := editor.rondine.body.position
        y := editor.project.sea_level
        extent := f32(90)
        // Rondine's defining presentation is its relationship to the water.
        // Give its showcase a local ocean card so the paired wake fans never
        // disappear against the otherwise sky-only vehicle backdrop.
        world_quad(
            {p.x - extent, y, p.z - extent},
            {p.x - extent, y, p.z + extent},
            {p.x + extent, y, p.z + extent},
            {p.x + extent, y, p.z - extent},
            {74, 145, 170, 255},
        )
        world_aircraft(editor)
        world_rondine_wake_fans(editor)
        world_showcase_aircraft_pilot(
            editor,
            editor.rondine.body.position,
            world_rondine_presentation_basis(editor),
            seat_height = .92,
        )
    } else {
        world_car(editor)
        world_showcase_car_pilot(editor)
    }
}

world_showcase_aircraft_pilot :: proc(
    editor: ^Editor,
    position: flight.Vec3,
    basis: flight.Basis,
    seat_height: f32 = .55,
) {
    rotation := math.atan2(-basis.forward.x, -basis.forward.z)
    seat_position := third_person.Vec3 {
        position.x + basis.up.x * seat_height,
        position.y + basis.up.y * seat_height,
        position.z + basis.up.z * seat_height,
    }
    world_mouse_model_parented(
        editor,
        {
            position = seat_position,
            rotation = rotation,
            accessory = editor.mouse_headgear,
            fur = editor.mouse_fur,
            pattern = editor.mouse_pattern,
            scarf_enabled = editor.mouse_scarf_enabled,
            scarf_color = editor.mouse_scarf_color,
            player_controlled = true,
            grounded = false,
            hide_tail = true,
            hide_hind_feet = true,
        },
        basis,
    )
}

world_rondine_pilot :: proc(editor: ^Editor) {
    if editor == nil ||
       !editor.in_map ||
       !editor.rondine_visible ||
       editor.pilot.mode != .Driving ||
       editor.pilot.vehicle != &editor.rondine.vehicle {
        return
    }
    world_showcase_aircraft_pilot(
        editor,
        editor.rondine.body.position,
        world_rondine_presentation_basis(editor),
        seat_height = .92,
    )
}

world_showcase_car_pilot :: proc(editor: ^Editor) {
    world_car_pilot_model(editor, editor.car_drive.steering, editor.car_drive.acceleration_feedback)
}

// Slightly smaller than the on-foot mouse so the upright seated silhouette
// fits inside the roadster instead of spanning the rear deck and windscreen.
CAR_PILOT_SCALE :: f32(.70)
CAR_PILOT_SEAT_Y :: f32(.31)
CAR_PILOT_SEAT_Z :: f32(-.03)
CAR_STEERING_WHEEL_Y :: f32(.59)
CAR_STEERING_WHEEL_Z :: f32(-.25)
CAR_STEERING_WHEEL_RADIUS :: f32(.17)
CAR_STEERING_COLUMN_Y :: f32(.53)
CAR_STEERING_COLUMN_Z :: f32(-.43)

// The steering wheel lies perpendicular to the column instead of floating in
// a vertical plane. Returning an authored car-local point from normalized rim
// coordinates keeps the rendered wheel and the driver's paw targets aligned.
car_steering_wheel_point :: proc(rim_x, rim_up: f32) -> [3]f32 {
    column_y := CAR_STEERING_WHEEL_Y - CAR_STEERING_COLUMN_Y
    column_z := CAR_STEERING_WHEEL_Z - CAR_STEERING_COLUMN_Z
    column_length := f32(math.sqrt(f64(column_y * column_y + column_z * column_z)))
    wheel_up_y := column_z / column_length
    wheel_up_z := -column_y / column_length
    return {
        rim_x * CAR_STEERING_WHEEL_RADIUS,
        CAR_STEERING_WHEEL_Y + rim_up * CAR_STEERING_WHEEL_RADIUS * wheel_up_y,
        CAR_STEERING_WHEEL_Z + rim_up * CAR_STEERING_WHEEL_RADIUS * wheel_up_z,
    }
}

World_Vehicle_Transform :: World_Model_Transform

world_vehicle_transform :: #force_inline proc(
    origin: third_person.Vec3,
    yaw, pitch, roll: f32,
) -> World_Vehicle_Transform {
    pitch_cos, pitch_sin := math.cos(pitch), math.sin(pitch)
    roll_cos, roll_sin := math.cos(roll), math.sin(roll)
    heading_cos, heading_sin := math.cos(yaw), math.sin(yaw)
    right := third_person.Vec3{-roll_cos * heading_sin, roll_sin, roll_cos * heading_cos}
    up := third_person.Vec3 {
        -pitch_sin * heading_cos + pitch_cos * roll_sin * heading_sin,
        pitch_cos * roll_cos,
        -pitch_sin * heading_sin - pitch_cos * roll_sin * heading_cos,
    }
    forward := third_person.Vec3 {
        pitch_cos * heading_cos + pitch_sin * roll_sin * heading_sin,
        pitch_sin * roll_cos,
        pitch_cos * heading_sin - pitch_sin * roll_sin * heading_cos,
    }
    return world_model_transform_from_basis(origin, right, up, forward)
}

// The authored car mesh faces local -Z, while Jolt vehicles face local +Z.
// Mesh local +X likewise maps to Jolt local -X. Apply that fixed 180-degree
// authoring conversion to the physical quaternion instead of decomposing and
// reconstructing an approximate Euler pose.
world_vehicle_transform_physics :: #force_inline proc(
    origin: third_person.Vec3,
    rotation: physics.Quat,
) -> World_Vehicle_Transform {
    physical_right := car_physics_rotate_vector(rotation, {1, 0, 0})
    physical_up := car_physics_rotate_vector(rotation, {0, 1, 0})
    physical_forward := car_physics_rotate_vector(rotation, {0, 0, 1})
    return world_model_transform_from_basis(
        origin,
        {-physical_right[0], -physical_right[1], -physical_right[2]},
        {physical_up[0], physical_up[1], physical_up[2]},
        {physical_forward[0], physical_forward[1], physical_forward[2]},
    )
}

world_car_transform :: #force_inline proc(editor: ^Editor) -> World_Vehicle_Transform {
    if editor.car_physics_body_rotation_valid {
        return world_vehicle_transform_physics(editor.car.position, editor.car_physics_body_rotation)
    }
    return world_vehicle_transform(
        editor.car.position,
        editor.car.yaw_radians,
        editor.car_drive.body_pitch,
        editor.car_drive.body_roll,
    )
}

world_trailer_transform :: #force_inline proc(editor: ^Editor) -> World_Vehicle_Transform {
    return world_vehicle_transform(
        editor.car_trailer_position,
        editor.car_trailer_yaw,
        editor.car_trailer.body_pitch,
        editor.car_trailer.body_roll,
    )
}

world_vehicle_vertex_world :: #force_inline proc(
    transform: World_Vehicle_Transform,
    position: [3]f32,
) -> third_person.Vec3 {
    return world_model_vertex_world(transform, position)
}

world_vehicle_normal_world :: #force_inline proc(
    transform: World_Vehicle_Transform,
    normal: [3]f32,
) -> third_person.Vec3 {
    return world_model_normal_world(transform, normal)
}

world_car_pilot_model :: proc(editor: ^Editor, steering, acceleration: f32) {
    rotation := editor.car.yaw_radians - math.PI * .5
    car_transform := world_car_transform(editor)
    seat := world_vehicle_vertex_world(car_transform, {0, CAR_PILOT_SEAT_Y, CAR_PILOT_SEAT_Z})
    world_mouse_model_scaled(
        editor,
        {
            // Settle the mouse into the low seat while leaving its head and
            // ears above the roadster's windscreen.
            position           = seat,
            rotation           = rotation,
            accessory          = editor.mouse_headgear,
            fur                = editor.mouse_fur,
            pattern            = editor.mouse_pattern,
            scarf_enabled      = editor.mouse_scarf_enabled,
            scarf_color        = editor.mouse_scarf_color,
            player_controlled  = true,
            grounded           = false,
            hide_tail          = true,
            hide_hind_feet     = true,
            driving_pose       = true,
            drive_steering     = steering,
            drive_acceleration = acceleration,
        },
        CAR_PILOT_SCALE,
    )
}

world_car_pilot :: proc(editor: ^Editor) {
    if !editor.in_map || editor.pilot.mode != .Driving || editor.pilot.vehicle != &editor.car do return
    world_car_pilot_model(editor, editor.car_drive.steering, editor.car_drive.acceleration_feedback)
}

@(no_instrumentation)
car_part_color :: #force_inline proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part) -> canvas2d.Color {
    if part == .Body {
        // A restrained petrol teal keeps the tiny roadster colorful against
        // Mediterranean roads without competing with the mouse's face and
        // paws for the focal contrast.
        return {29, 124, 145, 255}
    }
    if part == .Strap {
        // Warm oxblood leather separates the seat and dashboard from both the
        // chestnut driver and the cool body paint.
        return {82, 43, 40, 255}
    }
    if part == .Tail_Light {
        braking :=
            editor != nil && (editor.car_drive.handbrake_amount > .15 || editor.car_drive.acceleration_feedback < -.12)
        return braking ? canvas2d.Color{255, 68, 55, 255} : canvas2d.Color{145, 35, 34, 255}
    }
    return aircraft_part_color(part)
}

@(no_instrumentation)
trailer_part_color :: #force_inline proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part) -> canvas2d.Color {
    color := car_part_color(editor, part)
    if part == .Tail_Light {
        braking := editor.car_drive.handbrake_amount > .15 || editor.car_drive.acceleration_feedback < -.12
        if braking do color = {255, 76, 62, 255}
    }
    return color
}

car_authored_wheel_index :: #force_inline proc(position: [3]f32) -> int {
    front := position[2] < 0
    // Authored mesh +X maps to Jolt -X and authored -Z maps to Jolt +Z.
    if front do return position[0] < 0 ? 0 : 1
    return position[0] < 0 ? 2 : 3
}

car_authored_wheel_center :: #force_inline proc(index: int) -> [3]f32 {
    x := index == 0 || index == 2 ? -vehicles.CAR_WHEEL_TRACK_HALF : vehicles.CAR_WHEEL_TRACK_HALF
    z := index < 2 ? -vehicles.CAR_WHEELBASE_HALF : vehicles.CAR_WHEELBASE_HALF
    return {x, vehicles.CAR_WHEEL_CENTER_Y, z}
}

car_wheel_vertex_world :: #force_inline proc(editor: ^Editor, position: [3]f32) -> third_person.Vec3 {
    index := car_authored_wheel_index(position)
    wheel := editor.car_wheels[index]
    center := car_authored_wheel_center(index)
    local := position - center
    spin_cos, spin_sin := math.cos(wheel.rotation), math.sin(wheel.rotation)
    spun_y := local[1] * spin_cos - local[2] * spin_sin
    spun_z := local[1] * spin_sin + local[2] * spin_cos

    physical_right := car_physics_rotate_vector(editor.car_physics_body_rotation, {1, 0, 0})
    physical_up := car_physics_rotate_vector(editor.car_physics_body_rotation, {0, 1, 0})
    physical_forward := car_physics_rotate_vector(editor.car_physics_body_rotation, {0, 0, 1})
    steer_cos, steer_sin := math.cos(wheel.steering), math.sin(wheel.steering)
    wheel_right := physical_right * steer_cos - physical_forward * steer_sin
    wheel_forward := physical_forward * steer_cos + physical_right * steer_sin
    return {
        wheel.position[0] - local[0] * wheel_right[0] + spun_y * physical_up[0] - spun_z * wheel_forward[0],
        wheel.position[1] - local[0] * wheel_right[1] + spun_y * physical_up[1] - spun_z * wheel_forward[1],
        wheel.position[2] - local[0] * wheel_right[2] + spun_y * physical_up[2] - spun_z * wheel_forward[2],
    }
}

car_wheel_normal_world :: #force_inline proc(editor: ^Editor, position, normal: [3]f32) -> third_person.Vec3 {
    index := car_authored_wheel_index(position)
    wheel := editor.car_wheels[index]
    spin_cos, spin_sin := math.cos(wheel.rotation), math.sin(wheel.rotation)
    spun_y := normal[1] * spin_cos - normal[2] * spin_sin
    spun_z := normal[1] * spin_sin + normal[2] * spin_cos
    physical_right := car_physics_rotate_vector(editor.car_physics_body_rotation, {1, 0, 0})
    physical_up := car_physics_rotate_vector(editor.car_physics_body_rotation, {0, 1, 0})
    physical_forward := car_physics_rotate_vector(editor.car_physics_body_rotation, {0, 0, 1})
    steer_cos, steer_sin := math.cos(wheel.steering), math.sin(wheel.steering)
    wheel_right := physical_right * steer_cos - physical_forward * steer_sin
    wheel_forward := physical_forward * steer_cos + physical_right * steer_sin
    return {
        -normal[0] * wheel_right[0] + spun_y * physical_up[0] - spun_z * wheel_forward[0],
        -normal[0] * wheel_right[1] + spun_y * physical_up[1] - spun_z * wheel_forward[1],
        -normal[0] * wheel_right[2] + spun_y * physical_up[2] - spun_z * wheel_forward[2],
    }
}

world_car :: proc(editor: ^Editor) {
    car_position := editor.car.position
    trailer_position := editor.car_trailer_position
    center := (car_position + trailer_position) * .5
    separation := trailer_position - car_position
    radius := f32(math.sqrt(f64(linalg.dot(separation, separation)))) * .5 + 6
    // Retain near-frustum vehicles so their projected shadows cannot disappear
    // while the body itself is just outside the camera.
    if !world_sphere_in_view(editor, center, radius, 6) do return
    mesh := editor.car_base_mesh
    trailer_speed_squared :=
        editor.car_trailer.velocity.x * editor.car_trailer.velocity.x +
        editor.car_trailer.velocity.z * editor.car_trailer.velocity.z
    trailer_variant := 0
    if editor.car_trailer_attached {
        trailer_variant = 1
    } else if trailer_speed_squared < .25 {
        trailer_variant = 2
    }
    if world_renderer.trailer_baked_meshes[trailer_variant] == nil {
        world_renderer.trailer_baked_meshes[trailer_variant] = vehicles.simple_car_trailer_mesh(
            !editor.car_trailer_attached,
            editor.car_trailer_attached,
            !editor.car_trailer_attached && trailer_speed_squared < .25,
        )
    }
    if world_renderer.trailer_pose_mesh == nil {
        world_renderer.trailer_pose_mesh = new(vehicles.Aircraft_Mesh)
    }
    trailer := world_renderer.trailer_pose_mesh
    trailer^ = world_renderer.trailer_baked_meshes[trailer_variant]^
    vehicles.animate_trailer_wheels(trailer, editor.car_trailer.wheel_rotation)
    car_transform := world_car_transform(editor)
    trailer_transform := world_trailer_transform(editor)
    world_car_cockpit(editor, car_transform)
    for triangle in vehicles.mesh_triangles(mesh) {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        smooth_part :=
            a.part == .Body ||
            a.part == .Wheel ||
            a.part == .Rounded_Chrome ||
            a.part == .Rounded_Ivory ||
            a.part == .Headlight ||
            a.part == .Tail_Light
        if smooth_part {
            color := car_part_color(editor, a.part)
            roughness := f32(.48)
            #partial switch a.part {
            case .Body:
                roughness = .62
            case .Wheel:
                roughness = .82
            case .Rounded_Chrome:
                roughness = .22
            case .Rounded_Ivory:
                roughness = .68
            case .Headlight, .Tail_Light:
                roughness = .30
            }
            a_position :=
                a.part == .Wheel && editor.car_physics_body_rotation_valid ? car_wheel_vertex_world(editor, a.position) : world_vehicle_vertex_world(car_transform, a.position)
            b_position :=
                b.part == .Wheel && editor.car_physics_body_rotation_valid ? car_wheel_vertex_world(editor, b.position) : world_vehicle_vertex_world(car_transform, b.position)
            c_position :=
                c.part == .Wheel && editor.car_physics_body_rotation_valid ? car_wheel_vertex_world(editor, c.position) : world_vehicle_vertex_world(car_transform, c.position)
            a_normal :=
                a.part == .Wheel && editor.car_physics_body_rotation_valid ? car_wheel_normal_world(editor, a.position, a.normal) : world_vehicle_normal_world(car_transform, a.normal)
            b_normal :=
                b.part == .Wheel && editor.car_physics_body_rotation_valid ? car_wheel_normal_world(editor, b.position, b.normal) : world_vehicle_normal_world(car_transform, b.normal)
            c_normal :=
                c.part == .Wheel && editor.car_physics_body_rotation_valid ? car_wheel_normal_world(editor, c.position, c.normal) : world_vehicle_normal_world(car_transform, c.normal)
            world_triangle_smooth_lit(
                a_position,
                b_position,
                c_position,
                a_normal,
                b_normal,
                c_normal,
                color,
                color,
                color,
                roughness,
                a.part == .Body ? World_Material_Kind.Car_Paint : World_Material_Kind.BRDF,
                a.part == .Body ? Car_Paint_Finish.Metal_Flake : Car_Paint_Finish.Opaque,
            )
        } else {
            world_triangle(
                world_vehicle_vertex_world(car_transform, a.position),
                world_vehicle_vertex_world(car_transform, b.position),
                world_vehicle_vertex_world(car_transform, c.position),
                car_part_color(editor, a.part),
            )
        }
    }
    for triangle in vehicles.mesh_triangles(trailer) {
        a := trailer.vertices[triangle.a]
        b := trailer.vertices[triangle.b]
        c := trailer.vertices[triangle.c]
        color := trailer_part_color(editor, a.part)
        if a.part == .Body {
            world_triangle_smooth_lit(
                world_vehicle_vertex_world(trailer_transform, a.position),
                world_vehicle_vertex_world(trailer_transform, b.position),
                world_vehicle_vertex_world(trailer_transform, c.position),
                world_vehicle_normal_world(trailer_transform, a.normal),
                world_vehicle_normal_world(trailer_transform, b.normal),
                world_vehicle_normal_world(trailer_transform, c.normal),
                color,
                color,
                color,
                .62,
                .Car_Paint,
                .Metal_Flake,
            )
        } else {
            world_triangle(
                world_vehicle_vertex_world(trailer_transform, a.position),
                world_vehicle_vertex_world(trailer_transform, b.position),
                world_vehicle_vertex_world(trailer_transform, c.position),
                color,
            )
        }
    }
}

world_car_cockpit :: proc(editor: ^Editor, car_transform: World_Vehicle_Transform) {
    // Keep the wheel low enough for the mouse's forepaws to meet the rim
    // without lifting its elbows into the windscreen. Its plane follows the
    // raked column, tipping the upper rim naturally toward the windscreen.
    wheel_center := [3]f32{0, CAR_STEERING_WHEEL_Y, CAR_STEERING_WHEEL_Z}
    wheel_rotation := clamp(editor.car_drive.steering, -1, 1) * .55
    column_local := [3]f32{0, CAR_STEERING_COLUMN_Y, CAR_STEERING_COLUMN_Z}
    column := world_vehicle_vertex_world(car_transform, column_local)
    center := world_vehicle_vertex_world(car_transform, wheel_center)
    forward := linalg.normalize0(center - column)
    leather := canvas2d.Color{48, 39, 34, 255}
    spoke := canvas2d.Color{104, 83, 65, 255}
    world_tube_between(column, center, forward, .035, .035, spoke)
    SEGMENTS :: 12
    ring: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS) + wheel_rotation
        point := car_steering_wheel_point(math.cos(angle), math.sin(angle))
        ring[segment] = world_vehicle_vertex_world(car_transform, point)
    }
    for segment in 0 ..< SEGMENTS {
        world_tube_between(ring[segment], ring[(segment + 1) % SEGMENTS], forward, .026, .026, leather)
    }
    for segment in 0 ..< 3 {
        angle := f32(segment) * math.PI * 2 / 3 + wheel_rotation
        point := car_steering_wheel_point(math.cos(angle) * .88, math.sin(angle) * .88)
        rim := world_vehicle_vertex_world(car_transform, point)
        world_tube_between(center, rim, forward, .018, .018, spoke)
    }
}
