package main

import arch_walls "../packages/arch_walls"
import atmosphere "../packages/atmosphere"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

arch_wall_lab_config: arch_walls.Config
arch_wall_lab_path: arch_walls.Path
arch_wall_lab_shape := 0

arch_wall_lab_terrain :: proc(_: ^Editor, x, z: f32) -> Lab_Terrain_Sample {
    height := math.sin(x*.105)*1.15+math.sin(z*.14+x*.035)*.72+x*.035
    return {height=height,material=.18+height*.025}
}

arch_wall_lab_set_path :: proc(shape: int) {
    arch_wall_lab_shape = ((shape%3)+3)%3
    arch_wall_lab_path = {}
    switch arch_wall_lab_shape {
    case 0:
        arch_wall_lab_path.point_count=4
        arch_wall_lab_path.points[0]={-24,-8}; arch_wall_lab_path.points[1]={-10,7}
        arch_wall_lab_path.points[2]={8,-6}; arch_wall_lab_path.points[3]={25,5}
    case 1:
        arch_wall_lab_path.point_count=6
        arch_wall_lab_path.points[0]={-42,-4}; arch_wall_lab_path.points[1]={-28,8}
        arch_wall_lab_path.points[2]={-10,-7}; arch_wall_lab_path.points[3]={10,8}
        arch_wall_lab_path.points[4]={28,-5}; arch_wall_lab_path.points[5]={44,3}
    case 2:
        arch_wall_lab_path.point_count=6; arch_wall_lab_path.closed=true
        arch_wall_lab_path.points[0]={-18,0}; arch_wall_lab_path.points[1]={-9,-14}
        arch_wall_lab_path.points[2]={9,-14}; arch_wall_lab_path.points[3]={18,0}
        arch_wall_lab_path.points[4]={9,14}; arch_wall_lab_path.points[5]={-9,14}
    }
}

arch_wall_generator_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    arch_wall_lab_config = arch_walls.defaults()
    switch target {
    case "", "curve": arch_wall_lab_set_path(0)
    case "long": arch_wall_lab_set_path(1)
    case "closed", "courtyard": arch_wall_lab_set_path(2)
    case: return false
    }
    _ = lab_terrain_load(editor,{
        half_extent_x=64,half_extent_z=42,sea_level=-8,outside_height=0,outside_material=.18,
    },arch_wall_lab_terrain)
    editor.in_map=true
    editor.capture_world_only=false
    editor.postale_visible=false
    editor.libellula_visible=false
    editor.rondine_visible=false
    editor.project.sea_level=-8
    atmosphere.set_world_minutes(&editor.atmosphere,16*60)
    atmosphere.set_weather_override(&editor.atmosphere,.Clear)
    editor.atmosphere.weather=atmosphere.weather_for(.Clear)
    editor.atmosphere.paused=true
    editor.camera_pose=third_person.camera_look_at({35,22,34},{0,2,0})
    third_person.camera_set_pose(&editor.cameras,.Inspection,editor.camera_pose)
    third_person.camera_set_active(&editor.cameras,.Inspection)
    return true
}

arch_wall_lab_height :: proc(position: arch_walls.Vec2, data: rawptr) -> f32 {
    editor := cast(^Editor)data
    return terrain.sample_surface_height(&editor.project,0,position.x,position.y)
}

arch_wall_generator_lab_process_input :: proc(_: ^Editor) {
    if canvas2d.IsKeyPressed(.S) do arch_wall_lab_set_path(arch_wall_lab_shape+1)
    if canvas2d.IsKeyPressed(.LEFT) do arch_wall_lab_config.height=max(f32(1.4),arch_wall_lab_config.height-.2)
    if canvas2d.IsKeyPressed(.RIGHT) do arch_wall_lab_config.height=min(f32(7),arch_wall_lab_config.height+.2)
    if canvas2d.IsKeyPressed(.DOWN) do arch_wall_lab_config.thickness=max(f32(.25),arch_wall_lab_config.thickness-.05)
    if canvas2d.IsKeyPressed(.UP) do arch_wall_lab_config.thickness=min(f32(1.6),arch_wall_lab_config.thickness+.05)
    if canvas2d.IsKeyPressed(.A) do arch_wall_lab_config.arch_spacing=max(f32(4),arch_wall_lab_config.arch_spacing-1)
    if canvas2d.IsKeyPressed(.D) do arch_wall_lab_config.arch_spacing=min(f32(20),arch_wall_lab_config.arch_spacing+1)
}

arch_wall_span_has_opening :: proc(span: ^arch_walls.Span, plan: ^arch_walls.Plan) -> bool {
    midpoint := (span.station_from+span.station_to)*.5
    for arch in plan.arches {
        if abs(midpoint-arch.station)<arch.width*.5 do return true
    }
    return false
}

world_arch_wall_generator_lab :: proc(editor: ^Editor) {
    plan := arch_walls.generate(&arch_wall_lab_path,arch_wall_lab_config,arch_wall_lab_height,editor)
    defer arch_walls.dispose(&plan)
    stone := canvas2d.Color{166,154,128,255}
    coping := canvas2d.Color{205,193,164,255}
    ring := canvas2d.Color{222,207,171,255}
    for &span in plan.spans {
        if arch_wall_span_has_opening(&span,&plan) do continue
        from_ground := (span.left_from+span.right_from)*.5
        to_ground := (span.left_to+span.right_to)*.5
        a := third_person.Vec3{span.from.x,from_ground+arch_wall_lab_config.height*.5,span.from.y}
        b := third_person.Vec3{span.to.x,to_ground+arch_wall_lab_config.height*.5,span.to.y}
        world_box_between(a,b,{0,1,0},arch_wall_lab_config.thickness,arch_wall_lab_config.height,stone)
        world_box_between(
            {span.from.x,from_ground+arch_wall_lab_config.height+.09,span.from.y},
            {span.to.x,to_ground+arch_wall_lab_config.height+.09,span.to.y},
            {0,1,0},arch_wall_lab_config.thickness+.12,.18,coping,
        )
    }
    for arch in plan.arches {
        normal := arch_walls.Vec2{-arch.tangent.y,arch.tangent.x}
        yaw := math.atan2(arch.tangent.y,arch.tangent.x)
        // Voussoir blocks trace a semicircular ring. Their local width follows
        // the curve while their depth stays aligned to the spline tangent.
        radius := arch.width*.5
        center_y := arch.ground+arch.height-radius
        segments := max(6,arch_wall_lab_config.arch_segments)
        for segment in 0 ..< segments {
            angle := math.PI*f32(segment)/f32(segments-1)
            x := math.cos(angle)*radius
            y := center_y+math.sin(angle)*radius
            position := arch.position+normal*x
            block_width := math.PI*radius/f32(segments-1)+arch_wall_lab_config.arch_ring_thickness
            world_box_rotated({position.x,y,position.y},{block_width,arch_wall_lab_config.arch_ring_thickness,arch_wall_lab_config.thickness+.14},yaw,ring)
        }
        spandrel_height := arch_wall_lab_config.height-arch.height
        if spandrel_height > .05 {
            world_box_rotated(
                {arch.position.x,arch.ground+arch.height+spandrel_height*.5,arch.position.y},
                {arch.width,spandrel_height,arch_wall_lab_config.thickness},yaw,stone,
            )
        }
        jamb_height := max(f32(.2),arch.height-radius)
        sides := [2]f32{-1,1}
        for side in sides {
            position := arch.position+normal*side*radius
            world_box_rotated({position.x,arch.ground+jamb_height*.5,position.y},{arch_wall_lab_config.arch_ring_thickness,jamb_height,arch_wall_lab_config.thickness+.14},yaw,ring)
        }
    }
}

arch_wall_generator_lab_draw_ui :: proc(editor: ^Editor, _: i32, _: i32) {
    plan := arch_walls.generate(&arch_wall_lab_path,arch_wall_lab_config,arch_wall_lab_height,editor)
    defer arch_walls.dispose(&plan)
    panel := canvas2d.Rectangle{22,22,770,142}
    canvas2d.DrawRectangleRounded(panel,.10,8,{21,27,27,232})
    canvas2d.DrawRectangleRoundedLinesEx(panel,.10,8,1,{143,151,126,255})
    canvas2d.DrawTextEx(canvas2d.Font{},"ARCH + WALL GENERATOR LAB",{38,38},20,1,{237,228,194,255})
    status := fmt.ctprintf("%.1f M   %d SPANS   %d ARCHES   %.1f M HIGH   %.2f M THICK",plan.length,len(plan.spans),len(plan.arches),arch_wall_lab_config.height,arch_wall_lab_config.thickness)
    canvas2d.DrawTextEx(canvas2d.Font{},status,{38,72},13,1,{190,213,189,255})
    canvas2d.DrawTextEx(canvas2d.Font{},"S PATH   LEFT / RIGHT HEIGHT   UP / DOWN THICKNESS   A / D ARCH SPACING",{38,104},12,1,{199,198,177,255})
    canvas2d.DrawTextEx(canvas2d.Font{},"Walls sample both terrain edges; length adds spans without stretching them.",{38,132},12,1,{199,198,177,255})
}
