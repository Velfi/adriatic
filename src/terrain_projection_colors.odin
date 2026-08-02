package main

import air_effects "../packages/air_effects"
import atmosphere "../packages/atmosphere"
import flight "../packages/flight"
import postale_game "../packages/postale"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

@(no_instrumentation)
perspective_camera :: #force_inline proc(
    pose: third_person.Camera_Pose,
    focal_length: f32 = 1.35,
) -> Perspective_Camera {
    forward := linalg.normalize0((pose.target - pose.position))
    right := linalg.normalize0(linalg.cross(forward, third_person.Vec3{0, 1, 0}))
    return {
        position = pose.position,
        forward = forward,
        right = right,
        up = linalg.cross(right, forward),
        focal_length = focal_length,
    }
}

project_3d :: proc(camera: Perspective_Camera, point: third_person.Vec3, width, height: i32) -> Screen_Point {
    view := (point - camera.position)
    depth := linalg.dot(view, camera.forward)
    if depth <= .08 do return {}
    x := linalg.dot(view, camera.right) * camera.focal_length / depth
    y := linalg.dot(view, camera.up) * camera.focal_length / depth
    // Use the viewport height for both axes so pixels remain square on
    // widescreen targets. Scaling X by width stretches projected geometry by
    // the display aspect ratio.
    half_height := f32(height) * .5
    return {
        position = {f32(width) * .5 + x * half_height, f32(height) * .5 - y * half_height},
        depth = depth,
        visible = true,
    }
}

world_under_cursor :: proc(mouse, center: canvas2d.Vector2, scale: f32) -> (f32, f32) {
    a := (mouse.x - center.x) / scale
    b := (mouse.y - center.y) / (scale * .46)
    return (a + b) * .5, (b - a) * .5
}

@(no_instrumentation)
terrain_color_variation :: #force_inline proc(color: canvas2d.Color, x, z: f32) -> canvas2d.Color {
    // Layer kilometre- and field-scale waves so whole slopes and headlands
    // develop distinct color regions. Feeding the continental field back into
    // the other phases bends their otherwise straight bands into broad,
    // irregular patches. World-space sampling keeps the result stable across
    // clipmap levels and camera movement.
    continental := f32(math.sin(f64(x * .0017 + z * .0011 + .8)))
    regional := f32(math.sin(f64(x * -.0041 + z * .0033 + continental * 1.65 + 2.3)))
    field := f32(math.sin(f64(x * .0107 + z * -.0083 + continental * .9 + regional * .7)))
    local := f32(math.sin(f64(x * -.031 + z * .027 + regional * 1.1 + 1.4)))
    variation := continental * .38 + regional * .34 + field * .20 + local * .08

    // A warm/cool shift varies hue as well as brightness. Regional fields get
    // enough chroma to read from an overview, while the bounded range
    // preserves the authored material identity.
    warm := max(variation, 0)
    cool := max(-variation, 0)
    return {
        u8(clamp(f32(color.r) * (1 + variation * .10) + warm * 5, 0, 255)),
        u8(clamp(f32(color.g) * (1 + variation * .065) + cool * 3, 0, 255)),
        u8(clamp(f32(color.b) * (1 + variation * .035) + cool * 6, 0, 255)),
        color.a,
    }
}

@(no_instrumentation)
dune_color_field :: #force_inline proc(x, z: f32) -> f32 {
    // Crossed, incommensurate waves produce soft sand mottling without the
    // long parallel color bands used by the broader inland landscape.
    broad := f32(math.sin(f64(x * .018 + z * .029 + .7))) * f32(math.sin(f64(x * -.027 + z * .014 + 2.1)))
    local := f32(math.sin(f64(x * .071 + z * -.043 + 1.3))) * f32(math.sin(f64(x * .039 + z * .083 + 2.8)))
    ripple := f32(math.sin(f64(x * .19 + z * .081 + broad * .8))) * f32(math.sin(f64(x * -.047 + z * .16 + .4)))
    return broad * .58 + local * .29 + ripple * .13
}

@(no_instrumentation)
dune_color_variation :: #force_inline proc(color: canvas2d.Color, x, z: f32) -> canvas2d.Color {
    variation := dune_color_field(x, z)
    warm := max(variation, f32(0))
    cool := max(-variation, f32(0))
    return {
        u8(clamp(f32(color.r) * (1 + variation * .035) + warm * 2.5, 0, 255)),
        u8(clamp(f32(color.g) * (1 + variation * .025) + warm * 1.2, 0, 255)),
        u8(clamp(f32(color.b) * (1 + variation * .018) + cool * 1.8, 0, 255)),
        color.a,
    }
}
