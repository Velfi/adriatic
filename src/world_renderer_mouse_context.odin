package main

import third_person "zelda_engine:third_person"
import canvas2d "zelda_engine:canvas2d"

// Mouse_Render_Context holds the model-space inputs shared by the mouse's
// independently rendered clothing and accessory layers.
Mouse_Render_Context :: struct {
    editor:        ^Editor,
    model:         Mouse_Model,
    p:             third_person.Vec3,
    rotation:      f32,
    model_forward: third_person.Vec3,
    fur:           canvas2d.Color,
    ear:           canvas2d.Color,
    tooth:         canvas2d.Color,
}
