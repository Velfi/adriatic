package main

import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import windmills "../packages/windmills"
import "core:math"
import canvas "zelda_engine:canvas2d"

windmill_lab_seed := u32(1948)
windmill_lab_region := windmills.Region.Adriatic
windmill_lab_aegean_sails := 12
windmill_lab_rpm := f32(3.5)
windmill_lab_heading := f32(0)
windmill_lab_weather := atmosphere.Weather_Preset.Windy
windmill_lab_rotor_angle := f32(0)
windmill_lab_rotor_heading := f32(0)
windmill_lab_last_time := f32(0)
windmill_lab_rotor_initialized := false

windmill_lab_configure_camera :: proc(editor: ^Editor) {
    if windmill_lab_region == .Aegean {
        editor.camera_pose = third_person.camera_look_at({8.2, 6.5, 11.2}, {0, 4.65, 0})
    } else {
        editor.camera_pose = third_person.camera_look_at({7.8, 5.9, 10.7}, {0, 4.0, 0})
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

windmill_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    windmill_lab_seed = 1948
    windmill_lab_region = .Adriatic
    windmill_lab_aegean_sails = 12
    windmill_lab_rpm = 3.5
    windmill_lab_heading = 0
    windmill_lab_weather = .Windy
    windmill_lab_rotor_angle = 0
    windmill_lab_rotor_heading = windmill_lab_heading
    windmill_lab_last_time = 0
    windmill_lab_rotor_initialized = false
    switch target {
    case "", "adriatic", "stone", "eight-sail":
    case "adriatic-alt":
        windmill_lab_seed = 0xA31A71C
    case "adriatic-crosswind":
        windmill_lab_heading = .62
    case "adriatic-calm":
        windmill_lab_weather = .Clear
    case "adriatic-storm":
        windmill_lab_weather = .Storm
    case "aegean", "whitewashed", "aegean-twelve":
        windmill_lab_region = .Aegean
    case "aegean-alt":
        windmill_lab_seed = 0xAE6EA12
        windmill_lab_region = .Aegean
    case "aegean-crosswind":
        windmill_lab_region = .Aegean
        windmill_lab_heading = .28
    case "aegean-calm":
        windmill_lab_region = .Aegean
        windmill_lab_weather = .Clear
    case "aegean-storm":
        windmill_lab_region = .Aegean
        windmill_lab_weather = .Storm
    case "aegean-ten":
        windmill_lab_region = .Aegean
        windmill_lab_aegean_sails = 10
    case:
        return false
    }
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60 + 35)
    atmosphere.set_weather_override(&editor.atmosphere, windmill_lab_weather)
    editor.atmosphere.weather = atmosphere.weather_for(windmill_lab_weather)
    editor.atmosphere.paused = true
    windmill_lab_configure_camera(editor)
    return true
}

windmill_lab_color_scale :: proc(color: canvas.Color, scale: f32) -> canvas.Color {
    return {
        u8(clamp(f32(color.r) * scale, 0, 255)),
        u8(clamp(f32(color.g) * scale, 0, 255)),
        u8(clamp(f32(color.b) * scale, 0, 255)),
        color.a,
    }
}

windmill_lab_wall_color :: proc(plan: ^windmills.Plan, segment: int) -> canvas.Color {
    if plan.region == .Aegean {
        base := canvas.Color{232, 228, 207, 255}
        return windmill_lab_color_scale(base, 1 - f32(segment & 1) * .012)
    }
    stones := [4]canvas.Color{{151, 143, 126, 255}, {166, 156, 135, 255}, {139, 133, 119, 255}, {177, 164, 139, 255}}
    hash := windmills.mix(plan.seed + u32(segment) * 0x9e3779b9)
    return stones[int(hash % u32(len(stones)))]
}

windmill_lab_tower :: proc(plan: ^windmills.Plan) {
    bottom, top: [24]third_person.Vec3
    for segment in 0 ..< plan.wall_segments {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(plan.wall_segments)
        variation := f32(windmills.mix(plan.seed + u32(segment) * 17) & 255) / 255 - .5
        bottom_radius := plan.base_radius * (1 + variation * plan.wall_irregularity)
        top_radius := plan.top_radius * (1 + variation * plan.wall_irregularity * .45)
        bottom[segment] = {math.cos(angle) * bottom_radius, 0, math.sin(angle) * bottom_radius}
        top[segment] = {math.cos(angle) * top_radius, plan.tower_height, math.sin(angle) * top_radius}
    }
    for segment in 0 ..< plan.wall_segments {
        next := (segment + 1) % plan.wall_segments
        wall := windmill_lab_wall_color(plan, segment)
        world_quad(bottom[segment], top[segment], top[next], bottom[next], wall)
        world_triangle({0, plan.tower_height, 0}, top[next], top[segment], wall)
    }

    roof_radius := plan.top_radius + plan.cap_overhang
    roof_peak := third_person.Vec3{0, plan.tower_height + plan.cap_height, 0}
    for segment in 0 ..< plan.wall_segments {
        angle_a := (f32(segment) + .5) * math.PI * 2 / f32(plan.wall_segments)
        angle_b := (f32(segment + 1) + .5) * math.PI * 2 / f32(plan.wall_segments)
        a := third_person.Vec3{math.cos(angle_a) * roof_radius, plan.tower_height, math.sin(angle_a) * roof_radius}
        b := third_person.Vec3{math.cos(angle_b) * roof_radius, plan.tower_height, math.sin(angle_b) * roof_radius}
        roof := plan.region == .Aegean ? canvas.Color{130, 91, 52, 255} : canvas.Color{91, 66, 48, 255}
        if plan.region == .Aegean && segment & 1 == 0 do roof = {153, 111, 62, 255}
        world_triangle(a, roof_peak, b, roof)
        eave := windmill_lab_color_scale(roof, .72)
        next := (segment + 1) % plan.wall_segments
        world_quad(top[segment], a, b, top[next], eave)
        world_quad(top[next], b, a, top[segment], eave)
    }

    door := plan.region == .Aegean ? canvas.Color{57, 75, 78, 255} : canvas.Color{78, 52, 34, 255}
    forward := third_person.Vec3{math.sin(plan.entrance_heading), 0, math.cos(plan.entrance_heading)}
    world_box_rotated(
        forward * (plan.base_radius + .03) + third_person.Vec3{0, plan.door_height * .5, 0},
        {plan.door_width, plan.door_height, .18},
        plan.entrance_heading,
        door,
    )
    window_frame := plan.region == .Aegean ? canvas.Color{73, 100, 106, 255} : canvas.Color{91, 78, 61, 255}
    for index in 0 ..< plan.window_count {
        y := plan.tower_height * (.42 + f32(index) * .15)
        side := index & 1 == 0 ? f32(1) : f32(-1)
        x := side * plan.top_radius * .73
        z := plan.top_radius * .72
        world_box_rotated({x, y, z}, {.42, .58, .13}, 0, window_frame)
    }
}

windmill_lab_sails_draw :: proc(plan: ^windmills.Plan, rotor_angle: f32) {
    right := third_person.Vec3{math.cos(plan.heading), 0, -math.sin(plan.heading)}
    forward := third_person.Vec3{math.sin(plan.heading), 0, math.cos(plan.heading)}
    hub_center := forward * (plan.top_radius + .40) + third_person.Vec3{0, plan.hub_height, 0}
    angle_offset := plan.phase
    angle_offset += rotor_angle
    timber := plan.region == .Aegean ? canvas.Color{91, 59, 34, 255} : canvas.Color{78, 57, 39, 255}
    sailcloth := plan.region == .Aegean ? canvas.Color{232, 222, 190, 242} : canvas.Color{205, 193, 157, 242}
    for index in 0 ..< plan.sail_count {
        angle := angle_offset + f32(index) * math.PI * 2 / f32(plan.sail_count)
        radial := right * math.sin(angle) + third_person.Vec3{0, math.cos(angle), 0}
        tangent := right * math.cos(angle) + third_person.Vec3{0, -math.sin(angle), 0}
        root := hub_center + radial * plan.sail_root
        tip := hub_center + radial * plan.sail_length
        outer_a := tip - tangent * (plan.sail_tip_width * .54)
        outer_b := tip + tangent * (plan.sail_tip_width * .46)
        world_triangle(root, outer_b, outer_a, sailcloth)
        world_triangle(root, outer_a, outer_b, sailcloth)

        member_half := tangent * .028
        lift := forward * .014
        world_quad(
            hub_center - member_half + lift,
            hub_center + member_half + lift,
            tip + member_half + lift,
            tip - member_half + lift,
            timber,
        )

        // The rope from one antenna tip to the next gives the Mediterranean
        // rotor its characteristic wheel-like silhouette even with furled cloth.
        next_angle := angle_offset + f32(index + 1) * math.PI * 2 / f32(plan.sail_count)
        next_tip := third_person.Vec3 {
            hub_center.x + right.x * math.sin(next_angle) * plan.sail_length + forward.x * .008,
            plan.hub_height + math.cos(next_angle) * plan.sail_length,
            hub_center.z + right.z * math.sin(next_angle) * plan.sail_length + forward.z * .008,
        }
        rope_half := tangent * .012
        world_quad(tip - rope_half, tip + rope_half, next_tip + rope_half, next_tip - rope_half, timber)
    }
    world_vertical_disc_rotated(
        hub_center + forward * .05,
        plan.hub_radius,
        plan.hub_radius,
        .34,
        plan.heading,
        timber,
    )
}

windmill_lab_site :: proc(plan: ^windmills.Plan) {
    top, bottom: [16]third_person.Vec3
    depth := plan.region == .Aegean ? f32(.16) : f32(.24)
    color := plan.region == .Aegean ? canvas.Color{207, 201, 178, 255} : canvas.Color{139, 120, 80, 255}
    for segment in 0 ..< plan.site_segments {
        angle := plan.site_rotation + f32(segment) * math.PI * 2 / f32(plan.site_segments)
        variation := f32(0)
        if plan.site_irregularity > 0 {
            hash := windmills.mix(plan.seed ~ 0x4b415253 ~ u32(segment) * 0x9e3779b9)
            variation = (f32(hash & 255) / 255 - .5) * 2 * plan.site_irregularity
        }
        radius := plan.site_radius * (1 + variation)
        top[segment] = {math.cos(angle) * radius, 0, math.sin(angle) * radius}
        bottom[segment] = {top[segment].x, -depth, top[segment].z}
    }
    for segment in 0 ..< plan.site_segments {
        next := (segment + 1) % plan.site_segments
        world_triangle({0, 0, 0}, top[next], top[segment], color)
        world_triangle({0, 0, 0}, top[segment], top[next], color)
        side := windmill_lab_color_scale(color, .78)
        world_quad(top[next], bottom[next], bottom[segment], top[segment], side)
        world_quad(top[segment], bottom[segment], bottom[next], top[next], side)
    }
}

world_windmill_generator_lab :: proc(editor: ^Editor) {
    config := windmills.defaults(windmill_lab_region)
    config.sail_count = windmill_lab_region == .Aegean ? windmill_lab_aegean_sails : 8
    config.rpm = windmill_lab_rpm
    config.heading = windmill_lab_heading
    plan := windmills.generate(windmill_lab_seed, config)
    animated_plan := plan
    if !windmill_lab_rotor_initialized {
        windmill_lab_last_time = editor.map_time
        windmill_lab_rotor_heading = plan.heading
        windmill_lab_rotor_initialized = true
    } else {
        delta := clamp(editor.map_time - windmill_lab_last_time, f32(0), f32(.1))
        windmill_lab_last_time = editor.map_time
        target_heading := windmills.rotor_heading_for_wind(windmill_lab_rotor_heading, editor.atmosphere.weather.wind)
        windmill_lab_rotor_heading = windmills.approach_heading(
            windmill_lab_rotor_heading,
            target_heading,
            delta * .55,
        )
        animated_plan.heading = windmill_lab_rotor_heading
        local_rpm := windmills.rotor_rpm_for_wind(&animated_plan, editor.atmosphere.weather.wind)
        windmill_lab_rotor_angle += delta * local_rpm * math.PI * 2 / 60
    }
    windmill_lab_site(&plan)
    windmill_lab_tower(&plan)
    windmill_lab_sails_draw(&animated_plan, windmill_lab_rotor_angle)
}
