package arch_walls

import "core:testing"

sloped_ground :: proc(point: Vec2, _: rawptr) -> f32 { return point.x*.2+point.y*.05 }

@(test)
curved_wall_scales_with_length_and_follows_both_terrain_edges :: proc(t: ^testing.T) {
    config := defaults()
    short := Path{point_count=2}; short.points[0]={0,0}; short.points[1]={10,0}
    long := Path{point_count=4}; long.points[0]={0,0}; long.points[1]={10,3}; long.points[2]={20,-3}; long.points[3]={40,0}
    a := generate(&short,config,sloped_ground); defer dispose(&a)
    b := generate(&long,config,sloped_ground); defer dispose(&b)
    testing.expect(t,a.valid && b.valid)
    testing.expect(t,b.length>a.length)
    testing.expect(t,len(b.spans)>len(a.spans))
    edges_differ := false
    for span in b.spans {
        if span.left_from!=span.right_from || span.left_to!=span.right_to do edges_differ=true
    }
    testing.expect(t,edges_differ)
}

@(test)
arches_repeat_along_complete_spline :: proc(t: ^testing.T) {
    config := defaults(); config.arch_spacing=6
    path := Path{point_count=3}; path.points[0]={0,0}; path.points[1]={18,6}; path.points[2]={36,0}
    plan := generate(&path,config,nil); defer dispose(&plan)
    testing.expect(t,len(plan.arches)>=5)
    for arch in plan.arches do testing.expect(t,arch.station>0 && arch.station<plan.length)
}
