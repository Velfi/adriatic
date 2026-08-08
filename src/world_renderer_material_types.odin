package main
import "core:math"
import "core:testing"

import cinematic "../packages/cinematic"
import particles "../packages/particles"
import terrain "../packages/terrain"
import "core:math/linalg"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

World_Material_Kind :: enum u32 {
    Unshaded,
    Water,
    Terrain,
    Foliage,
    Road,
    BRDF,
    Eye,
    Vehicle,
    Acorn,
    Bottle_Cap,
    Emissive,
    Emissive_Pool,
    Architecture,
    Glass,
    Emissive_Halo,
    Sailor_Hat,
    Sign,
    Lighthouse_Glitter,
    Leaf,
    Petal,
    Fountain_Water,
    Car_Paint,
    Material_Lab,
    Settlement_Material,
    Fog_Shell,
    Rock,
    Bark,
}
