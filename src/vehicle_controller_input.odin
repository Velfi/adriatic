package main

import vehicles "../packages/vehicles"
import canvas2d "zelda_engine:canvas2d"

// Vehicle_Controller_Input is the contract between a controller and a
// controllable vehicle. Vehicle simulation must not know which device supplied
// these normalized values.
Vehicle_Controller_Input :: struct {
    throttle, steering: f32,
    handbrake:          bool,
}

Live_Vehicle_Control :: struct {
    active:     bool,
    throttle:   f32,
    steering:   f32,
    handbrake:  bool,
    expires_at: f64,
}

live_vehicle_control: Live_Vehicle_Control

car_controller_input :: proc() -> Vehicle_Controller_Input {
    result := Vehicle_Controller_Input{}
    if canvas2d.IsKeyDown(.W) || canvas2d.IsKeyDown(.UP) do result.throttle += 1
    if canvas2d.IsKeyDown(.S) || canvas2d.IsKeyDown(.DOWN) do result.throttle -= 1
    if canvas2d.IsKeyDown(.A) || canvas2d.IsKeyDown(.LEFT) do result.steering -= 1
    if canvas2d.IsKeyDown(.D) || canvas2d.IsKeyDown(.RIGHT) do result.steering += 1
    if canvas2d.GamepadAvailable() {
        result.throttle += max(gamepad_axis(.Right_Trigger), f32(0))
        result.throttle -= max(gamepad_axis(.Left_Trigger), f32(0))
        result.steering = stronger_axis(result.steering, gamepad_axis(.Left_X))
    }
    result.throttle = clamp(result.throttle, -1, 1)
    result.steering = clamp(result.steering, -1, 1)
    result.handbrake = input_action_down(.Handbrake)
    if live_vehicle_control.active {
        if canvas2d.GetTime() < live_vehicle_control.expires_at {
            result.throttle = live_vehicle_control.throttle
            result.steering = live_vehicle_control.steering
            result.handbrake = live_vehicle_control.handbrake
        } else {
            live_vehicle_control = {}
        }
    }
    return result
}

car_controller_step :: proc(
    editor: ^Editor,
    control: Vehicle_Controller_Input,
    surface: vehicles.Car_Drive_Surface,
    delta_seconds, listener_yaw: f32,
) -> (
    impact_severity, impact_slide_speed, impact_obliqueness, impact_pan: f32,
) {
    return car_physics_step(
        editor,
        control.throttle,
        control.steering,
        control.handbrake,
        surface,
        delta_seconds,
        listener_yaw,
    )
}
